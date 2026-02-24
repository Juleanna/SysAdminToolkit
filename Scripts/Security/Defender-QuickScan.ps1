$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора для сканування Defender."
    exit 1
}

if (-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
    Write-Error "Сканер Defender недоступний на цій системі."
    exit 1
}

$svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Error "Сервіс WinDefend не знайдено."
    exit 1
}

if ($svc.Status -ne 'Running') {
    try {
        Start-Service -Name WinDefend -ErrorAction Stop
        Write-Host "WinDefend запущено." -ForegroundColor Yellow
    } catch {
        Write-Error "Не вдалося запустити WinDefend: $($_.Exception.Message)"
        exit 1
    }
}

try {
    Write-Host "Запускаю швидке сканування Defender..." -ForegroundColor Cyan
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Write-Host "Швидке сканування завершено." -ForegroundColor Green
    $threats = Get-MpThreat -ErrorAction SilentlyContinue
    if ($threats) {
        $threats | Select-Object ThreatName,Resources,DetectionTime,ActionSuccess | Format-Table -AutoSize
    } else {
        Write-Host "Загроз не виявлено." -ForegroundColor Green
    }
} catch {
    Write-Error "Не вдалося запустити сканування: $($_.Exception.Message)"
    exit 1
}
