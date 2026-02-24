$paths = @(
    $env:TEMP,
    "$env:WINDIR\Temp"
)

$totalFreed = 0
foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }
    Write-Host "Очищення $p..."
    $items = Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue
    $sizeBefore = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    $sizeAfter = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    $freed = [math]::Round((($sizeBefore - $sizeAfter) / 1MB), 1)
    if ($freed -gt 0) { $totalFreed += $freed }
}

Write-Host "Тимчасові файли очищено. Звільнено ~${totalFreed} MB." -ForegroundColor Green
