<#
.SYNOPSIS
    Формує звіт про проблемні заплановані завдання.
.DESCRIPTION
    Аналізує всі заплановані завдання та групує їх за категоріями:
    невдалі (LastTaskResult != 0), вимкнені та застарілі (не виконувались більше StaleDays днів).
    Використовує Get-ScheduledTask та Get-ScheduledTaskInfo.
.PARAMETER StaleDays
    Кількість днів без виконання для визначення завдання як застарілого. За замовчуванням 30.
.EXAMPLE
    .\ScheduledTask-Report.ps1
    Показує звіт з порогом застарілості 30 днів.
.EXAMPLE
    .\ScheduledTask-Report.ps1 -StaleDays 60
    Показує звіт з порогом застарілості 60 днів.
#>
param(
    [int]$StaleDays = 30
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск звіту заплановних завдань (StaleDays=$StaleDays)" -Level INFO

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop
} catch {
    $msg = "Не вдалося отримати список заплановних завдань: $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Error $msg
    exit 1
}

if (-not $tasks -or $tasks.Count -eq 0) {
    Write-Host "Заплановані завдання не знайдено." -ForegroundColor Yellow
    exit 0
}

$now = Get-Date
$staleThreshold = $now.AddDays(-$StaleDays)

$failed = @()
$disabled = @()
$stale = @()

foreach ($task in $tasks) {
    try {
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue

        $taskName = $task.TaskName
        $taskPath = $task.TaskPath
        $state = $task.State
        $lastResult = if ($info) { $info.LastTaskResult } else { $null }
        $lastRunTime = if ($info) { $info.LastRunTime } else { $null }
        $nextRunTime = if ($info) { $info.NextRunTime } else { $null }

        # Перевірка: вимкнене завдання
        if ($state -eq 'Disabled') {
            $disabled += [pscustomobject]@{
                Name       = $taskName
                Path       = $taskPath
                State      = $state
                LastResult = $lastResult
                LastRun    = if ($lastRunTime -and $lastRunTime.Year -gt 1999) { $lastRunTime.ToString("yyyy-MM-dd HH:mm") } else { "Ніколи" }
            }
            continue
        }

        # Перевірка: невдале завдання (LastTaskResult != 0)
        if ($null -ne $lastResult -and $lastResult -ne 0) {
            $failed += [pscustomobject]@{
                Name       = $taskName
                Path       = $taskPath
                State      = $state
                LastResult = "0x{0:X8}" -f $lastResult
                LastRun    = if ($lastRunTime -and $lastRunTime.Year -gt 1999) { $lastRunTime.ToString("yyyy-MM-dd HH:mm") } else { "Ніколи" }
                NextRun    = if ($nextRunTime -and $nextRunTime.Year -gt 1999) { $nextRunTime.ToString("yyyy-MM-dd HH:mm") } else { "-" }
            }
        }

        # Перевірка: застаріле завдання (давно не виконувалось)
        if ($lastRunTime -and $lastRunTime.Year -gt 1999 -and $lastRunTime -lt $staleThreshold) {
            $daysSinceRun = [math]::Floor(($now - $lastRunTime).TotalDays)
            $stale += [pscustomobject]@{
                Name         = $taskName
                Path         = $taskPath
                State        = $state
                LastRun      = $lastRunTime.ToString("yyyy-MM-dd HH:mm")
                DaysSinceRun = $daysSinceRun
            }
        }
    } catch {
        Write-TkLog "Помилка обробки завдання '$($task.TaskName)': $($_.Exception.Message)" -Level WARN
    }
}

# Вивід результатів
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Звіт заплановних завдань" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Невдалі
Write-Host "--- Невдалі завдання (LastTaskResult != 0) ---" -ForegroundColor Red
if ($failed.Count -gt 0) {
    $failed | Format-Table -AutoSize
} else {
    Write-Host "  Невдалих завдань не знайдено.`n" -ForegroundColor Green
}

# Вимкнені
Write-Host "--- Вимкнені завдання ---" -ForegroundColor Yellow
if ($disabled.Count -gt 0) {
    $disabled | Format-Table -AutoSize
} else {
    Write-Host "  Вимкнених завдань не знайдено.`n" -ForegroundColor Green
}

# Застарілі
Write-Host "--- Застарілі завдання (не виконувались > $StaleDays днів) ---" -ForegroundColor Yellow
if ($stale.Count -gt 0) {
    $stale | Format-Table -AutoSize
} else {
    Write-Host "  Застарілих завдань не знайдено.`n" -ForegroundColor Green
}

# Підсумок
Write-Host "--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Всього завдань: $($tasks.Count)"
Write-Host "Невдалі:        $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Вимкнені:       $($disabled.Count)" -ForegroundColor $(if ($disabled.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "Застарілі:      $($stale.Count)" -ForegroundColor $(if ($stale.Count -gt 0) { "Yellow" } else { "Green" })

Write-TkLog "Звіт завдань: всього=$($tasks.Count), невдалі=$($failed.Count), вимкнені=$($disabled.Count), застарілі=$($stale.Count)" -Level INFO
