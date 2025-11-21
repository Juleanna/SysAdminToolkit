. "$PSScriptRoot\ToolkitCommon.psm1"

param(
    [string]$OutputRoot
)

if (-not $OutputRoot) {
    $OutputRoot = Join-Path (Get-ToolkitRoot) "Logs"
}

if (-not (Test-Path $OutputRoot)) {
    New-Item -Path $OutputRoot -ItemType Directory | Out-Null
}

$pc = $env:COMPUTERNAME
$folder = Join-Path $OutputRoot ("Logs_" + $pc + "_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

New-Item -ItemType Directory -Path $folder | Out-Null

wevtutil epl System (Join-Path $folder 'System.evtx')
wevtutil epl Application (Join-Path $folder 'Application.evtx')

Get-CimInstance Win32_ComputerSystem | Out-File (Join-Path $folder 'ComputerSystem.txt')
Get-CimInstance Win32_OperatingSystem | Out-File (Join-Path $folder 'OS.txt')

Write-Host "Логи собраны в $folder"
