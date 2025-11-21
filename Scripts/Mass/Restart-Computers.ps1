param(
    [string]$ListPath = ".\\pcs.txt"
)

if (-not (Test-Path $ListPath)) {
    Write-Error "Файл со списком не найден: $ListPath"
    exit 1
}

$pcs = Get-Content $ListPath
foreach ($pc in $pcs) {
    Write-Host "Перезагрузка $pc..."
    Restart-Computer -ComputerName $pc -Force -ErrorAction SilentlyContinue
}
