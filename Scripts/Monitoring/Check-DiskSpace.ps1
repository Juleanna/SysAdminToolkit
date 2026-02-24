<#
.SYNOPSIS
    Перевіряє вільний простір на локальних фіксованих дисках.
.DESCRIPTION
    Отримує інформацію про всі фіксовані томи через Get-Volume (DriveType=Fixed)
    та порівнює відсоток використання з пороговими значеннями з конфігурації
    (DiskSpaceWarningPercent, DiskSpaceCriticalPercent).
    Виводить кольоровий звіт: зелений — норма, жовтий — попередження,
    червоний — критичний рівень. Для критичних дисків записує попередження
    у лог через Write-TkLog.
.PARAMETER None
    Скрипт не приймає параметрів. Пороги зчитуються з ToolkitConfig.json.
.EXAMPLE
    .\Check-DiskSpace.ps1
    Перевіряє всі фіксовані диски та виводить кольоровий звіт.
#>
param()

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск перевірки дискового простору" -Level INFO

$cfg = Get-ToolkitConfig
$warnPercent = if ($cfg.DiskSpaceWarningPercent) { $cfg.DiskSpaceWarningPercent } else { 80 }
$critPercent = if ($cfg.DiskSpaceCriticalPercent) { $cfg.DiskSpaceCriticalPercent } else { 95 }

try {
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } -ErrorAction Stop
} catch {
    $msg = "Не вдалося отримати інформацію про томи: $($_.Exception.Message)"
    Write-TkLog $msg -Level ERROR
    Write-Host $msg -ForegroundColor Red
    exit 1
}

if (-not $volumes -or @($volumes).Count -eq 0) {
    Write-Host "Фіксовані томи не знайдено." -ForegroundColor Yellow
    Write-TkLog "Фіксовані томи не знайдено" -Level WARN
    exit 0
}

Write-Host "`n=== Дисковий простір (фіксовані диски) ===" -ForegroundColor Cyan
Write-Host "Пороги: Попередження >= ${warnPercent}% | Критичний >= ${critPercent}%`n" -ForegroundColor Cyan

$results = @()

foreach ($vol in $volumes) {
    try {
        $totalGB     = [math]::Round($vol.Size / 1GB, 2)
        $freeGB      = [math]::Round($vol.SizeRemaining / 1GB, 2)
        $usedGB      = [math]::Round(($vol.Size - $vol.SizeRemaining) / 1GB, 2)
        $percentUsed = if ($vol.Size -gt 0) { [math]::Round(($vol.Size - $vol.SizeRemaining) / $vol.Size * 100, 1) } else { 0 }

        $obj = [pscustomobject]@{
            DriveLetter = "$($vol.DriveLetter):"
            Label       = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "-" }
            TotalGB     = $totalGB
            UsedGB      = $usedGB
            FreeGB      = $freeGB
            PercentUsed = $percentUsed
        }
        $results += $obj

        # Визначення кольору за порогами
        if ($percentUsed -ge $critPercent) {
            $color = "Red"
            $status = "КРИТИЧНИЙ"
        } elseif ($percentUsed -ge $warnPercent) {
            $color = "Yellow"
            $status = "ПОПЕРЕДЖЕННЯ"
        } else {
            $color = "Green"
            $status = "НОРМА"
        }

        # Візуальна смужка використання
        $barLength    = 30
        $filledLength = [math]::Floor($percentUsed / 100 * $barLength)
        $emptyLength  = $barLength - $filledLength
        $bar = "[" + ("=" * $filledLength) + (" " * $emptyLength) + "]"

        $line = "{0,-5} {1,-16} {2,8} GB / {3,8} GB  Вільно: {4,8} GB  ({5,5}%)  {6}  {7}" -f `
            $obj.DriveLetter, $obj.Label, $usedGB, $totalGB, $freeGB, $percentUsed, $bar, $status
        Write-Host $line -ForegroundColor $color

        # Логування критичних та попереджувальних станів
        if ($percentUsed -ge $critPercent) {
            Write-TkLog "КРИТИЧНО: Диск $($obj.DriveLetter) використано ${percentUsed}% ($usedGB/$totalGB GB)" -Level ERROR
        } elseif ($percentUsed -ge $warnPercent) {
            Write-TkLog "ПОПЕРЕДЖЕННЯ: Диск $($obj.DriveLetter) використано ${percentUsed}% ($usedGB/$totalGB GB)" -Level WARN
        }

    } catch {
        Write-TkLog "Помилка обробки тому $($vol.DriveLetter): $($_.Exception.Message)" -Level WARN
        Write-Host "Помилка обробки тому $($vol.DriveLetter): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Підсумок
$critCount = ($results | Where-Object { $_.PercentUsed -ge $critPercent }).Count
$warnCount = ($results | Where-Object { $_.PercentUsed -ge $warnPercent -and $_.PercentUsed -lt $critPercent }).Count
$okCount   = ($results | Where-Object { $_.PercentUsed -lt $warnPercent }).Count

Write-Host "`n--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Всього дисків: $($results.Count) | " -NoNewline
Write-Host "Норма: $okCount" -ForegroundColor Green -NoNewline
Write-Host " | " -NoNewline
Write-Host "Попередження: $warnCount" -ForegroundColor Yellow -NoNewline
Write-Host " | " -NoNewline
Write-Host "Критичний: $critCount" -ForegroundColor Red

if ($critCount -gt 0) {
    Write-TkLog "УВАГА! Критичний рівень дискового простору на $critCount диск(ах)" -Level ERROR
} elseif ($warnCount -gt 0) {
    Write-TkLog "Попередження: низький дисковий простір на $warnCount диск(ах)" -Level WARN
} else {
    Write-TkLog "Дисковий простір в нормі на всіх $($results.Count) дисках" -Level INFO
}
