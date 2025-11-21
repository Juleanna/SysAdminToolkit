. "$PSScriptRoot\..\Utils\ToolkitCommon.psm1"

$root = Get-ToolkitRoot
$inventoryPath = $root
$files = Get-ChildItem -Path $inventoryPath -Filter "PC_Inventory_*.json" -ErrorAction SilentlyContinue |
         Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-14) } |
         Sort-Object LastWriteTime -Descending

if (-not $files -or $files.Count -eq 0) {
    Write-Error "Не найдено свежих файлов инвентаризации за последние 14 дней."
    exit 1
}

$latest = $files[0]
Write-Host "Отправляем $($latest.FullName) в Telegram..."
& "$PSScriptRoot\Send-TGFile.ps1" -FilePath $latest.FullName -Caption "Инвентаризация с $($env:COMPUTERNAME)"
