<#
.SYNOPSIS
    Створює резервну копію всіх об'єктів групової політики (GPO).

.DESCRIPTION
    Перевіряє наявність модуля GroupPolicy (RSAT) та виконує резервне копіювання
    всіх GPO за допомогою Get-GPO -All та Backup-GPO. Кожен об'єкт групової
    політики зберігається окремо у вказану папку. Для кожного GPO виводиться
    статус операції (успіх або помилка).

.PARAMETER BackupPath
    Шлях до папки для збереження резервних копій GPO. За замовчуванням
    використовується DefaultBackupPath\GPO з конфігурації тулкіту.

.EXAMPLE
    .\Backup-GPO.ps1
    Створює резервну копію всіх GPO у стандартну папку.

.EXAMPLE
    .\Backup-GPO.ps1 -BackupPath "D:\Backups\GPO\manual"
    Створює резервну копію всіх GPO у вказану папку.
#>

param(
    [string]$BackupPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Assert-Administrator

$cfg = Get-ToolkitConfig

if (-not $BackupPath) {
    $BackupPath = Join-Path $cfg.DefaultBackupPath "GPO"
}

Write-TkLog "Backup-GPO: запуск резервного копіювання об'єктів групової політики" -Level INFO

# Перевірка наявності модуля GroupPolicy (RSAT)
Write-Host "Перевірка наявності модуля GroupPolicy..." -ForegroundColor Gray

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Host "[ПОМИЛКА] Модуль GroupPolicy не встановлено." -ForegroundColor Red
    Write-Host "          Встановіть RSAT (Remote Server Administration Tools) для роботи з GPO." -ForegroundColor Yellow
    Write-Host "          Команда: Install-WindowsFeature GPMC  або" -ForegroundColor Gray
    Write-Host "          Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -ForegroundColor Gray
    Write-TkLog "Backup-GPO: модуль GroupPolicy не знайдено. Потрібно встановити RSAT." -Level ERROR
    exit 1
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Host "[OK] Модуль GroupPolicy завантажено." -ForegroundColor Green
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося завантажити модуль GroupPolicy: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Backup-GPO: помилка імпорту модуля GroupPolicy: $($_.Exception.Message)" -Level ERROR
    exit 1
}

# Створення папки якщо не існує
if (-not (Test-Path $BackupPath)) {
    try {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "[OK] Створено папку: $BackupPath" -ForegroundColor Green
    } catch {
        Write-Host "[ПОМИЛКА] Не вдалося створити папку '$BackupPath': $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Backup-GPO: не вдалося створити папку '$BackupPath': $($_.Exception.Message)" -Level ERROR
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Резервне копіювання GPO" -ForegroundColor Cyan
Write-Host "  Папка: $BackupPath" -ForegroundColor Gray
Write-Host "  Дата:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$errorCount = 0

try {
    $allGPOs = Get-GPO -All -ErrorAction Stop

    if (-not $allGPOs -or $allGPOs.Count -eq 0) {
        Write-Host "[ІНФО] Об'єктів групової політики не знайдено." -ForegroundColor Yellow
        Write-TkLog "Backup-GPO: GPO не знайдено в домені" -Level WARN
        exit 0
    }

    Write-Host "Знайдено GPO: $($allGPOs.Count)" -ForegroundColor White
    Write-Host ""

    $allGPOs | ForEach-Object {
        $gpo = $_
        $gpoName = $gpo.DisplayName

        try {
            $backupResult = Backup-GPO -Guid $gpo.Id -Path $BackupPath -ErrorAction Stop
            Write-Host "  [OK]      $gpoName (ID: $($backupResult.Id))" -ForegroundColor Green
            Write-TkLog "Backup-GPO: успішно — '$gpoName'" -Level INFO
            $successCount++
        } catch {
            Write-Host "  [ПОМИЛКА] $gpoName : $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Backup-GPO: помилка для '$gpoName': $($_.Exception.Message)" -Level WARN
            $errorCount++
        }
    }
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати список GPO: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Backup-GPO: критична помилка — $($_.Exception.Message)" -Level ERROR
    exit 1
}

# Підсумок
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Результат:" -ForegroundColor Cyan
Write-Host "  Успішно збережено: $successCount" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "  Помилки:           $errorCount" -ForegroundColor Red
}
Write-Host "  Всього GPO:       $($allGPOs.Count)" -ForegroundColor White
Write-Host "  Збережено у:       $BackupPath" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan

Write-TkLog "Backup-GPO: завершено. Успішно: $successCount, помилок: $errorCount з $($allGPOs.Count) GPO" -Level INFO
