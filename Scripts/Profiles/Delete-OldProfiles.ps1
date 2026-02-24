param(
    [int]$DaysOld = 90,
    [switch]$Force
)

$cutoff = (Get-Date).AddDays(-[math]::Abs($DaysOld))

$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and
    $_.LocalPath -notlike "*$env:USERNAME*" -and
    $_.LastUseTime -and
    $_.LastUseTime -lt $cutoff
}

if (-not $profiles) {
    Write-Host "Немає профілів старших за $DaysOld днів для видалення." -ForegroundColor Green
    exit 0
}

Write-Host "Знайдено профілів для видалення: $(@($profiles).Count)" -ForegroundColor Yellow
$profiles | ForEach-Object {
    Write-Host "  $($_.LocalPath) — останнє використання: $($_.LastUseTime)"
}

if (-not $Force) {
    Write-Host "`nДля видалення запустіть з параметром -Force" -ForegroundColor Yellow
    exit 0
}

foreach ($p in $profiles) {
    try {
        Write-Host "Видаляю профіль: $($p.LocalPath)..."
        Remove-CimInstance $p -ErrorAction Stop
        Write-Host "  Видалено." -ForegroundColor Green
    } catch {
        Write-Warning "Не вдалося видалити $($p.LocalPath): $($_.Exception.Message)"
    }
}
