<#
.SYNOPSIS
    Показує звіт про дисковий простір для всіх фіксованих томів.

.DESCRIPTION
    Використовує Get-Volume для отримання інформації про фіксовані диски.
    Відображає букву диска, мітку, загальний/використаний/вільний простір у ГБ
    та відсоток використання. Кольорове кодування за порогами з конфігу:
    менше DiskSpaceWarningPercent - зелений, від Warning до Critical - жовтий,
    вище DiskSpaceCriticalPercent - червоний.

.PARAMETER ExportHtml
    Якщо вказано, експортує звіт у HTML-файл за допомогою Export-TkReport.

.EXAMPLE
    .\Disk-SpaceReport.ps1
    Виводить таблицю дискового простору у консоль.

.EXAMPLE
    .\Disk-SpaceReport.ps1 -ExportHtml
    Виводить таблицю у консоль та зберігає HTML-звіт у папку Reports.
#>
param(
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig
$warningPercent  = if ($cfg.DiskSpaceWarningPercent)  { $cfg.DiskSpaceWarningPercent }  else { 80 }
$criticalPercent = if ($cfg.DiskSpaceCriticalPercent) { $cfg.DiskSpaceCriticalPercent } else { 95 }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Звіт про дисковий простір" -ForegroundColor Cyan
Write-Host "  Поріг попередження: ${warningPercent}% | Критичний: ${criticalPercent}%" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    $volumes = Get-Volume -ErrorAction Stop | Where-Object {
        $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.Size -gt 0
    }
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати дані томів: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Disk-SpaceReport: Не вдалося отримати дані томів: $($_.Exception.Message)" -Level ERROR
    exit 1
}

if (-not $volumes) {
    Write-Host "Фіксованих томів не знайдено." -ForegroundColor Yellow
    exit 0
}

# Заголовок таблиці
$header = "{0,-6} {1,-20} {2,12} {3,12} {4,12} {5,10}" -f "Диск", "Мітка", "Всього ГБ", "Зайнято ГБ", "Вільно ГБ", "Зайнято %"
Write-Host $header -ForegroundColor White
Write-Host ("-" * 75) -ForegroundColor Gray

$reportData = @()

foreach ($vol in $volumes) {
    $totalGB = [math]::Round($vol.Size / 1GB, 2)
    $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $usedGB  = [math]::Round(($vol.Size - $vol.SizeRemaining) / 1GB, 2)
    $usedPct = [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 1)

    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "-" }
    $drive = "$($vol.DriveLetter):"

    $line = "{0,-6} {1,-20} {2,12} {3,12} {4,12} {5,9}%" -f $drive, $label, $totalGB, $usedGB, $freeGB, $usedPct

    if ($usedPct -ge $criticalPercent) {
        Write-Host $line -ForegroundColor Red
    } elseif ($usedPct -ge $warningPercent) {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Green
    }

    $reportData += [pscustomobject]@{
        Диск        = $drive
        Мітка       = $label
        "Всього ГБ" = $totalGB
        "Зайнято ГБ"= $usedGB
        "Вільно ГБ" = $freeGB
        "Зайнято %"  = $usedPct
    }
}

Write-Host ""
Write-Host "Всього томів: $($volumes.Count)" -ForegroundColor Cyan

if ($ExportHtml) {
    try {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportPath = Join-Path $reportDir "DiskSpace_${timestamp}.html"
        $result = Export-TkReport -Data $reportData -Path $reportPath -Title "Звіт про дисковий простір" -Format HTML
        Write-Host "HTML-звіт збережено: $result" -ForegroundColor Green
    } catch {
        Write-Host "[ПОМИЛКА] Не вдалося експортувати HTML-звіт: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Disk-SpaceReport: Помилка експорту HTML: $($_.Exception.Message)" -Level ERROR
    }
}

Write-TkLog "Disk-SpaceReport: Перевірено $($volumes.Count) том(ів)" -Level INFO
