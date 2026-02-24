param(
    [string]$OutputRoot
)

Import-Module "$PSScriptRoot\ToolkitCommon.psm1" -Force

if (-not $OutputRoot) {
    $OutputRoot = Join-Path (Get-ToolkitRoot) "Logs"
}

if (-not (Test-Path $OutputRoot)) {
    New-Item -Path $OutputRoot -ItemType Directory | Out-Null
}

$pc = $env:COMPUTERNAME
$folder = Join-Path $OutputRoot ("Logs_" + $pc + "_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

try {
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
} catch {
    Write-Error "Не вдалося створити папку: $($_.Exception.Message)"
    exit 1
}

Write-Host "Збір логів..." -ForegroundColor Cyan

try { wevtutil epl System (Join-Path $folder 'System.evtx') } catch { Write-Warning "System.evtx: $_" }
try { wevtutil epl Application (Join-Path $folder 'Application.evtx') } catch { Write-Warning "Application.evtx: $_" }

try { Get-CimInstance Win32_ComputerSystem | Out-File (Join-Path $folder 'ComputerSystem.txt') -Encoding UTF8 } catch { Write-Warning "ComputerSystem: $_" }
try { Get-CimInstance Win32_OperatingSystem | Out-File (Join-Path $folder 'OS.txt') -Encoding UTF8 } catch { Write-Warning "OS: $_" }

Write-Host "Логи зібрано в $folder" -ForegroundColor Green
