<#
.SYNOPSIS
    Налаштування автоматичного відновлення служби Windows при збоях.

.DESCRIPTION
    Дозволяє переглядати, вмикати або вимикати автоматичне відновлення
    для вказаної служби. При ввімкненні встановлює перезапуск служби
    при першому та другому збоях, скидання лічильника після 1 доби (86400 с).
    Використовує sc.exe failure для конфігурації.
    Потребує прав адміністратора для режимів Enable та Disable.

.PARAMETER ServiceName
    Ім'я служби для налаштування (обов'язковий параметр).

.PARAMETER Mode
    Режим роботи:
      Status  — показати поточні налаштування відновлення (за замовчуванням).
      Enable  — увімкнути автоматичний перезапуск при збоях.
      Disable — вимкнути автоматичне відновлення (скинути дії при збоях).

.EXAMPLE
    .\Service-AutoRecover.ps1 -ServiceName "Spooler"
    Показує поточні налаштування відновлення служби друку.

.EXAMPLE
    .\Service-AutoRecover.ps1 -ServiceName "Spooler" -Mode Enable
    Вмикає автоматичний перезапуск при збоях для служби друку.

.EXAMPLE
    .\Service-AutoRecover.ps1 -ServiceName "wuauserv" -Mode Disable
    Вимикає автоматичне відновлення для служби оновлення Windows.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [ValidateSet('Status','Enable','Disable')]
    [string]$Mode = 'Status'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if ($Mode -ne 'Status') {
    Assert-Administrator
}

try {
    # Перевірка існування служби
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "Службу '$ServiceName' не знайдено на цьому комп'ютері." -ForegroundColor Red
        Write-TkLog "Service-AutoRecover: службу '$ServiceName' не знайдено." -Level ERROR
        exit 1
    }

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Автовідновлення служби: $($svc.DisplayName) ($ServiceName)" -ForegroundColor Cyan
    Write-Host "  Режим: $Mode" -ForegroundColor Cyan
    Write-Host "  Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Функція для отримання поточних налаштувань відновлення
    function Get-RecoveryInfo {
        param([string]$Name)
        try {
            $output = & sc.exe qfailure $Name 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Не вдалося отримати налаштування відновлення для '$Name'." -ForegroundColor Red
                return $null
            }
            return ($output | Out-String)
        } catch {
            Write-Host "Помилка виконання sc.exe: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }

    switch ($Mode) {
        'Status' {
            Write-Host "Поточний стан служби: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })
            Write-Host ""
            Write-Host "Налаштування відновлення при збоях:" -ForegroundColor Yellow
            Write-Host "-" * 50 -ForegroundColor DarkGray

            $info = Get-RecoveryInfo -Name $ServiceName
            if ($info) {
                $lines = $info -split "`r?`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

                    if ($trimmed -match 'RESTART|ПЕРЕЗАПУСК') {
                        Write-Host "  $trimmed" -ForegroundColor Green
                    } elseif ($trimmed -match 'RUN PROCESS|ЗАПУСК') {
                        Write-Host "  $trimmed" -ForegroundColor Yellow
                    } elseif ($trimmed -match 'REBOOT|ПЕРЕЗАВАНТАЖЕННЯ') {
                        Write-Host "  $trimmed" -ForegroundColor Red
                    } else {
                        Write-Host "  $trimmed" -ForegroundColor White
                    }
                }
            }

            Write-TkLog "Service-AutoRecover: перегляд налаштувань відновлення для '$ServiceName'." -Level INFO
        }

        'Enable' {
            Write-Host "Увімкнення автоматичного відновлення..." -ForegroundColor Yellow
            Write-Host "  Перший збій:  перезапуск служби" -ForegroundColor White
            Write-Host "  Другий збій:  перезапуск служби" -ForegroundColor White
            Write-Host "  Скидання лічильника: через 1 добу (86400 с)" -ForegroundColor White
            Write-Host ""

            try {
                # sc.exe failure <ім'я> reset= 86400 actions= restart/60000/restart/60000//0
                # reset=86400 — скидання лічильника збоїв через 86400 секунд (1 доба)
                # actions: перший збій — restart через 60с, другий — restart через 60с, третій — нічого
                $scArgs = "failure `"$ServiceName`" reset= 86400 actions= restart/60000/restart/60000//0"
                $result = & cmd.exe /c "sc.exe $scArgs" 2>&1
                $output = $result | Out-String

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Автоматичне відновлення успішно увімкнено." -ForegroundColor Green
                    Write-TkLog "Service-AutoRecover: увімкнено автовідновлення для '$ServiceName' (restart/restart, reset=86400)." -Level INFO
                } else {
                    Write-Host "Помилка налаштування sc.exe failure:" -ForegroundColor Red
                    Write-Host $output -ForegroundColor Red
                    Write-TkLog "Service-AutoRecover: помилка увімкнення для '$ServiceName' — $output" -Level ERROR
                    exit 1
                }
            } catch {
                Write-Host "Помилка виконання sc.exe: $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Service-AutoRecover: помилка виконання sc.exe — $($_.Exception.Message)" -Level ERROR
                exit 1
            }

            Write-Host ""
            Write-Host "Перевірка нових налаштувань:" -ForegroundColor Yellow
            $info = Get-RecoveryInfo -Name $ServiceName
            if ($info) {
                $lines = $info -split "`r?`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                    Write-Host "  $trimmed" -ForegroundColor White
                }
            }
        }

        'Disable' {
            Write-Host "Вимкнення автоматичного відновлення..." -ForegroundColor Yellow
            Write-Host ""

            try {
                # Скидання: жодних дій при збоях
                $scArgs = "failure `"$ServiceName`" reset= 0 actions= //0//0//0"
                $result = & cmd.exe /c "sc.exe $scArgs" 2>&1
                $output = $result | Out-String

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Автоматичне відновлення вимкнено." -ForegroundColor Green
                    Write-TkLog "Service-AutoRecover: вимкнено автовідновлення для '$ServiceName'." -Level INFO
                } else {
                    Write-Host "Помилка налаштування sc.exe failure:" -ForegroundColor Red
                    Write-Host $output -ForegroundColor Red
                    Write-TkLog "Service-AutoRecover: помилка вимкнення для '$ServiceName' — $output" -Level ERROR
                    exit 1
                }
            } catch {
                Write-Host "Помилка виконання sc.exe: $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Service-AutoRecover: помилка виконання sc.exe — $($_.Exception.Message)" -Level ERROR
                exit 1
            }

            Write-Host ""
            Write-Host "Перевірка нових налаштувань:" -ForegroundColor Yellow
            $info = Get-RecoveryInfo -Name $ServiceName
            if ($info) {
                $lines = $info -split "`r?`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                    Write-Host "  $trimmed" -ForegroundColor White
                }
            }
        }
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Завершено." -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

} catch {
    Write-Host "Критична помилка: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Service-AutoRecover: критична помилка — $($_.Exception.Message)" -Level ERROR
    exit 1
}
