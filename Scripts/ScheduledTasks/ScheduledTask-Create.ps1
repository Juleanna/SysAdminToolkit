<#
.SYNOPSIS
    Створює заплановане завдання для виконання PowerShell-скрипта.
.DESCRIPTION
    Створює нове заплановане завдання Windows, що запускає вказаний PowerShell-скрипт
    за обраним розкладом (щоденно, щотижнево, при запуску системи або при вході користувача).
    Потребує прав адміністратора.
.PARAMETER TaskName
    Назва завдання. Обов'язковий параметр.
.PARAMETER ScriptPath
    Шлях до PowerShell-скрипта для виконання. Обов'язковий параметр.
.PARAMETER TriggerType
    Тип тригера: Daily, Weekly, AtStartup, AtLogon.
.PARAMETER Time
    Час виконання у форматі HH:mm. За замовчуванням '08:00'. Використовується для Daily та Weekly.
.EXAMPLE
    .\ScheduledTask-Create.ps1 -TaskName "DailyBackup" -ScriptPath "D:\Scripts\backup.ps1" -TriggerType Daily
    Створює щоденне завдання о 08:00.
.EXAMPLE
    .\ScheduledTask-Create.ps1 -TaskName "StartupCheck" -ScriptPath "D:\Scripts\check.ps1" -TriggerType AtStartup
    Створює завдання, що виконується при запуску системи.
.EXAMPLE
    .\ScheduledTask-Create.ps1 -TaskName "WeeklyReport" -ScriptPath "D:\Scripts\report.ps1" -TriggerType Weekly -Time "09:30"
    Створює щотижневе завдання о 09:30.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,

    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,

    [ValidateSet('Daily','Weekly','AtStartup','AtLogon')]
    [string]$TriggerType = 'Daily',

    [string]$Time = '08:00'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

# Перевірка прав адміністратора
Assert-Administrator

Write-TkLog "Створення завдання '$TaskName' (скрипт: $ScriptPath, тригер: $TriggerType, час: $Time)" -Level INFO

# Перевірка наявності скрипта
if (-not (Test-Path $ScriptPath)) {
    $msg = "Скрипт не знайдено: $ScriptPath"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Перевірка чи завдання вже існує
try {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $msg = "Завдання з назвою '$TaskName' вже існує. Видаліть його спочатку або оберіть іншу назву."
        Write-TkLog $msg -Level WARN
        Write-Warning $msg
        exit 1
    }
} catch {
    # Ігноруємо помилку - означає завдання не існує
}

# Парсинг часу
try {
    $timeSpan = [TimeSpan]::Parse($Time)
} catch {
    $msg = "Невірний формат часу: '$Time'. Очікується формат HH:mm (наприклад, 08:00)."
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Створення тригера
try {
    $trigger = switch ($TriggerType) {
        'Daily' {
            New-ScheduledTaskTrigger -Daily -At $Time -ErrorAction Stop
        }
        'Weekly' {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time -ErrorAction Stop
        }
        'AtStartup' {
            New-ScheduledTaskTrigger -AtStartup -ErrorAction Stop
        }
        'AtLogon' {
            New-ScheduledTaskTrigger -AtLogon -ErrorAction Stop
        }
    }
} catch {
    $msg = "Не вдалося створити тригер ($TriggerType): $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Створення дії (запуск PowerShell зі скриптом)
try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
        -ErrorAction Stop
} catch {
    $msg = "Не вдалося створити дію завдання: $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Налаштування завдання (запуск з найвищими привілеями)
try {
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ErrorAction Stop
} catch {
    $msg = "Не вдалося створити налаштування завдання: $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

# Реєстрація завдання
try {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Створено SysAdminToolkit: $ScriptPath" `
        -ErrorAction Stop | Out-Null

    Write-Host "Завдання '$TaskName' успішно створено." -ForegroundColor Green
    Write-Host "  Скрипт:  $ScriptPath"
    Write-Host "  Тригер:  $TriggerType"
    if ($TriggerType -in 'Daily','Weekly') {
        Write-Host "  Час:     $Time"
    }
    Write-Host "  Запуск:  SYSTEM (найвищі привілеї)"
    Write-TkLog "Завдання '$TaskName' успішно створено" -Level INFO
} catch {
    $msg = "Не вдалося зареєструвати завдання '$TaskName': $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}
