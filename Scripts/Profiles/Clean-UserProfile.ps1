$dirs = @(
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent"
)

foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        Write-Host "Пропускаю (не існує): $d" -ForegroundColor Gray
        continue
    }
    Write-Host "Очищення: $d"
    $before = (Get-ChildItem "$d" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    Remove-Item "$d\*" -Recurse -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem "$d" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    $removed = $before - $after
    Write-Host "  Видалено елементів: $removed" -ForegroundColor Green
}
