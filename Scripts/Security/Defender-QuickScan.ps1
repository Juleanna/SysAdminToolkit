$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Требуются права администратора для запуска проверки Defender."
    exit 1
}

if (-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
    Write-Error "Модуль Defender (Defender/WindowsSecurity) недоступен на этой системе."
    exit 1
}

$svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Error "Сервис WinDefend не найден."
    exit 1
}

if ($svc.Status -ne 'Running') {
    try {
        Start-Service -Name WinDefend -ErrorAction Stop
        Write-Host "WinDefend был запущен." -ForegroundColor Yellow
    } catch {
        Write-Error "Не удалось запустить WinDefend: $($_.Exception.Message)"
        exit 1
    }
}

try {
    Write-Host "Стартует быстрая проверка Defender..." -ForegroundColor Cyan
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Write-Host "Быстрая проверка завершена." -ForegroundColor Green
    Get-MpThreat | Select-Object ThreatName,Resources,DetectionTime,ActionSuccess | Format-Table -AutoSize
} catch {
    Write-Error "Не удалось выполнить проверку: $($_.Exception.Message)"
    exit 1
}
