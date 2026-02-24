<#
.SYNOPSIS
    Перезапуск служби Windows з обробкою залежностей.

.DESCRIPTION
    Перезапускає вказану службу з урахуванням залежних служб.
    Перевіряє існування служби, відображає залежності, виконує зупинку
    та повторний запуск, а потім перевіряє, що служба працює.
    Потребує прав адміністратора.

.PARAMETER ServiceName
    Ім'я служби для перезапуску (обов'язковий параметр).

.PARAMETER Force
    Примусовий перезапуск без підтвердження, включаючи зупинку залежних служб.

.EXAMPLE
    .\Service-Restart.ps1 -ServiceName "Spooler"
    Перезапускає службу друку з відображенням залежностей.

.EXAMPLE
    .\Service-Restart.ps1 -ServiceName "wuauserv" -Force
    Примусово перезапускає службу оновлення Windows разом із залежними службами.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [switch]$Force
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Assert-Administrator

try {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Перезапуск служби: $ServiceName" -ForegroundColor Cyan
    Write-Host "  Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Перевірка існування служби
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "Службу '$ServiceName' не знайдено на цьому комп'ютері." -ForegroundColor Red
        Write-TkLog "Service-Restart: службу '$ServiceName' не знайдено." -Level ERROR
        exit 1
    }

    Write-Host "Служба:       $($svc.ServiceName)" -ForegroundColor White
    Write-Host "Відображення: $($svc.DisplayName)" -ForegroundColor White
    Write-Host "Поточний стан: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })
    Write-Host ""

    # Перевірка залежностей
    $dependentServices = Get-Service -Name $ServiceName -DependentServices -ErrorAction SilentlyContinue
    $requiredServices = Get-Service -Name $ServiceName -RequiredServices -ErrorAction SilentlyContinue

    if ($requiredServices -and $requiredServices.Count -gt 0) {
        Write-Host "Ця служба залежить від:" -ForegroundColor Yellow
        foreach ($dep in $requiredServices) {
            $depColor = if ($dep.Status -eq 'Running') { 'Green' } else { 'Red' }
            Write-Host "  - $($dep.ServiceName) ($($dep.DisplayName)) [$($dep.Status)]" -ForegroundColor $depColor
        }
        Write-Host ""
    }

    $runningDependents = @()
    if ($dependentServices -and $dependentServices.Count -gt 0) {
        Write-Host "Залежні служби (будуть зупинені):" -ForegroundColor Yellow
        foreach ($dep in $dependentServices) {
            $depColor = if ($dep.Status -eq 'Running') { 'Green' } else { 'Red' }
            Write-Host "  - $($dep.ServiceName) ($($dep.DisplayName)) [$($dep.Status)]" -ForegroundColor $depColor
            if ($dep.Status -eq 'Running') {
                $runningDependents += $dep
            }
        }
        Write-Host ""
    }

    # Підтвердження якщо є залежні служби і не вказано -Force
    if ($runningDependents.Count -gt 0 -and -not $Force) {
        Write-Host "УВАГА: $($runningDependents.Count) залежних служб працюють і будуть зупинені." -ForegroundColor Yellow
        $confirm = Read-Host "Продовжити? (Y/N)"
        if ($confirm -notin @('Y','y','Д','д','Yes','yes','Так','так')) {
            Write-Host "Операцію скасовано користувачем." -ForegroundColor Yellow
            Write-TkLog "Service-Restart: перезапуск '$ServiceName' скасовано користувачем." -Level INFO
            exit 0
        }
    }

    # Зупинка залежних служб
    if ($runningDependents.Count -gt 0) {
        Write-Host "Зупинка залежних служб..." -ForegroundColor Yellow
        foreach ($dep in $runningDependents) {
            try {
                Write-Host "  Зупинка $($dep.ServiceName)..." -ForegroundColor Gray
                Stop-Service -Name $dep.ServiceName -Force -ErrorAction Stop
                Write-Host "  $($dep.ServiceName) зупинено." -ForegroundColor Green
            } catch {
                Write-Host "  Не вдалося зупинити $($dep.ServiceName): $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Service-Restart: не вдалося зупинити залежну службу $($dep.ServiceName) — $($_.Exception.Message)" -Level ERROR
            }
        }
        Write-Host ""
    }

    # Зупинка основної служби
    if ($svc.Status -eq 'Running') {
        Write-Host "Зупинка служби '$ServiceName'..." -ForegroundColor Yellow
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            # Очікування повної зупинки
            $svc.WaitForStatus('Stopped', (New-TimeSpan -Seconds 30))
            Write-Host "Службу '$ServiceName' зупинено." -ForegroundColor Green
        } catch {
            Write-Host "Не вдалося зупинити службу '$ServiceName': $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Service-Restart: не вдалося зупинити '$ServiceName' — $($_.Exception.Message)" -Level ERROR
            exit 1
        }
    } else {
        Write-Host "Служба '$ServiceName' вже зупинена. Запускаємо..." -ForegroundColor Yellow
    }

    # Запуск основної служби
    Write-Host "Запуск служби '$ServiceName'..." -ForegroundColor Yellow
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        $svc = Get-Service -Name $ServiceName
        $svc.WaitForStatus('Running', (New-TimeSpan -Seconds 30))
        Write-Host "Службу '$ServiceName' запущено." -ForegroundColor Green
    } catch {
        Write-Host "Не вдалося запустити службу '$ServiceName': $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Service-Restart: не вдалося запустити '$ServiceName' — $($_.Exception.Message)" -Level ERROR
        exit 1
    }

    # Запуск залежних служб
    if ($runningDependents.Count -gt 0) {
        Write-Host ""
        Write-Host "Запуск залежних служб..." -ForegroundColor Yellow
        foreach ($dep in $runningDependents) {
            try {
                Write-Host "  Запуск $($dep.ServiceName)..." -ForegroundColor Gray
                Start-Service -Name $dep.ServiceName -ErrorAction Stop
                Write-Host "  $($dep.ServiceName) запущено." -ForegroundColor Green
            } catch {
                Write-Host "  Не вдалося запустити $($dep.ServiceName): $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Service-Restart: не вдалося запустити залежну службу $($dep.ServiceName) — $($_.Exception.Message)" -Level WARN
            }
        }
    }

    # Фінальна перевірка
    Write-Host ""
    $finalSvc = Get-Service -Name $ServiceName
    if ($finalSvc.Status -eq 'Running') {
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  Службу '$ServiceName' успішно перезапущено." -ForegroundColor Green
        Write-Host "  Поточний стан: $($finalSvc.Status)" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-TkLog "Service-Restart: службу '$ServiceName' успішно перезапущено." -Level INFO
    } else {
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host "  УВАГА: Служба '$ServiceName' не працює після перезапуску!" -ForegroundColor Red
        Write-Host "  Поточний стан: $($finalSvc.Status)" -ForegroundColor Red
        Write-Host "============================================================" -ForegroundColor Red
        Write-TkLog "Service-Restart: служба '$ServiceName' не працює після перезапуску (стан: $($finalSvc.Status))." -Level ERROR
        exit 1
    }

} catch {
    Write-Host "Критична помилка під час перезапуску служби: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Service-Restart: критична помилка — $($_.Exception.Message)" -Level ERROR
    exit 1
}
