param(
    [string]$ListPath,
    [switch]$Force
)

if (-not $ListPath) {
    $ListPath = Join-Path $PSScriptRoot "..\..\pcs.txt"
}

if (-not (Test-Path $ListPath)) {
    Write-Error "Файл зі списком не знайдено: $ListPath"
    exit 1
}

$pcs = Get-Content $ListPath -Encoding UTF8 | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }

if (-not $pcs) {
    Write-Host "Список комп'ютерів порожній." -ForegroundColor Yellow
    exit 0
}

Write-Host "Комп'ютери для перезавантаження:" -ForegroundColor Cyan
$pcs | ForEach-Object { Write-Host "  $_" }

if (-not $Force) {
    Write-Host "`nДля перезавантаження запустіть з параметром -Force" -ForegroundColor Yellow
    exit 0
}

foreach ($pc in $pcs) {
    $pc = $pc.Trim()
    Write-Host "Перезавантаження $pc..." -NoNewline
    try {
        Restart-Computer -ComputerName $pc -Force -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " ПОМИЛКА: $($_.Exception.Message)" -ForegroundColor Red
    }
}
