<#
.SYNOPSIS
    Експортує всі заплановані завдання Windows у XML-файли.

.DESCRIPTION
    Створює резервну копію всіх запланованих завдань (Scheduled Tasks) у форматі XML.
    Для кожного завдання викликається Export-ScheduledTask, а результат зберігається
    як окремий файл із іменем TaskPath_TaskName.xml (символи \ замінюються на _).
    По завершенні виводиться кількість успішно експортованих завдань.

.PARAMETER BackupPath
    Шлях до папки для збереження XML-файлів. За замовчуванням використовується
    DefaultBackupPath\ScheduledTasks з конфігурації тулкіту.

.EXAMPLE
    .\Backup-ScheduledTask.ps1
    Експортує всі завдання у стандартну папку резервних копій.

.EXAMPLE
    .\Backup-ScheduledTask.ps1 -BackupPath "D:\Backups\Tasks"
    Експортує завдання у вказану папку.
#>

param(
    [string]$BackupPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig

if (-not $BackupPath) {
    $BackupPath = Join-Path $cfg.DefaultBackupPath "ScheduledTasks"
}

Write-TkLog "Backup-ScheduledTask: запуск резервного копіювання запланованих завдань" -Level INFO

# Створення папки якщо не існує
if (-not (Test-Path $BackupPath)) {
    try {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "[OK] Створено папку: $BackupPath" -ForegroundColor Green
    } catch {
        Write-Host "[ПОМИЛКА] Не вдалося створити папку '$BackupPath': $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Backup-ScheduledTask: не вдалося створити папку '$BackupPath': $($_.Exception.Message)" -Level ERROR
        exit 1
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Експорт запланованих завдань" -ForegroundColor Cyan
Write-Host "  Папка: $BackupPath" -ForegroundColor Gray
Write-Host "  Дата:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$exportedCount = 0
$errorCount = 0

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop

    if (-not $tasks -or $tasks.Count -eq 0) {
        Write-Host "[ІНФО] Запланованих завдань не знайдено." -ForegroundColor Yellow
        Write-TkLog "Backup-ScheduledTask: завдань не знайдено" -Level WARN
        exit 0
    }

    Write-Host "Знайдено завдань: $($tasks.Count)" -ForegroundColor White
    Write-Host ""

    $tasks | ForEach-Object {
        $task = $_
        $taskPath = $task.TaskPath
        $taskName = $task.TaskName

        # Формуємо ім'я файлу: TaskPath_TaskName.xml (замінюємо \ на _)
        $safePath = ($taskPath -replace '\\', '_').Trim('_')
        $safeName = $taskName -replace '[\\/:*?"<>|]', '_'

        $fileName = if ($safePath) {
            "${safePath}_${safeName}.xml"
        } else {
            "${safeName}.xml"
        }

        $filePath = Join-Path $BackupPath $fileName

        try {
            $xml = Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
            Set-Content -Path $filePath -Value $xml -Encoding UTF8 -ErrorAction Stop
            $exportedCount++
        } catch {
            Write-Host "  [ПОМИЛКА] $taskPath$taskName : $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Backup-ScheduledTask: помилка експорту '$taskPath$taskName': $($_.Exception.Message)" -Level WARN
            $errorCount++
        }
    }
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати список завдань: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Backup-ScheduledTask: критична помилка — $($_.Exception.Message)" -Level ERROR
    exit 1
}

# Підсумок
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Результат:" -ForegroundColor Cyan
Write-Host "  Експортовано завдань: $exportedCount" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "  Помилки:             $errorCount" -ForegroundColor Red
}
Write-Host "  Збережено у:         $BackupPath" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan

Write-TkLog "Backup-ScheduledTask: завершено. Експортовано: $exportedCount, помилок: $errorCount" -Level INFO
