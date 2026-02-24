param(
    [Parameter(Mandatory=$true)]
    [string]$Source,
    [string]$Dest
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig
if (-not $Dest) {
    $Dest = $cfg.DefaultBackupPath
}

if (-not (Test-Path $Source)) {
    Write-Error "Исходный путь не найден: $Source"
    exit 1
}

if (-not (Test-Path $Dest)) {
    New-Item -Path $Dest -ItemType Directory | Out-Null
}

$Date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$Target = Join-Path $Dest ("Backup_" + $Date)

Write-Host "Копируем $Source в $Target..."

try {
    robocopy $Source $Target /MIR /R:1 /W:2 /NFL /NDL /NP /NJH /NJS | Out-Null
    Write-Host "Резервная копия сохранена в $Target"
} catch {
    Write-Error "Не удалось выполнить копирование: $($_.Exception.Message)"
    exit 1
}
