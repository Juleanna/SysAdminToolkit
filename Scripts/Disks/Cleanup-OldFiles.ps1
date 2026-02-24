<#
.SYNOPSIS
    Видаляє файли старші за вказану кількість днів у заданих шляхах.

.DESCRIPTION
    Сканує вказану папку на наявність файлів, що старші за N днів.
    У режимі WhatIf лише показує, що було б видалено, із загальним розміром.
    Без WhatIf видаляє файли та повідомляє кількість і звільнений простір.

.PARAMETER Path
    Обов'язковий. Шлях до папки для очищення.

.PARAMETER DaysOld
    Кількість днів. Файли старші за цю кількість будуть видалені. За замовчуванням 30.

.PARAMETER Filter
    Фільтр файлів (наприклад, '*.log', '*.tmp'). За замовчуванням '*' (всі файли).

.PARAMETER WhatIf
    Якщо вказано, лише показує які файли було б видалено без фактичного видалення.

.EXAMPLE
    .\Cleanup-OldFiles.ps1 -Path "C:\Temp" -DaysOld 60 -WhatIf
    Показує файли старші за 60 днів у C:\Temp без видалення.

.EXAMPLE
    .\Cleanup-OldFiles.ps1 -Path "D:\Logs" -DaysOld 90 -Filter "*.log"
    Видаляє всі .log файли старші за 90 днів у D:\Logs.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [int]$DaysOld = 30,

    [string]$Filter = '*',

    [switch]$WhatIf
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Очищення старих файлів" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Перевірка існування шляху
if (-not (Test-Path $Path)) {
    Write-Host "[ПОМИЛКА] Шлях не знайдено: $Path" -ForegroundColor Red
    Write-TkLog "Cleanup-OldFiles: Шлях не знайдено: $Path" -Level ERROR
    exit 1
}

$cutoffDate = (Get-Date).AddDays(-[math]::Abs($DaysOld))

Write-Host "Шлях:    $Path" -ForegroundColor White
Write-Host "Фільтр:  $Filter" -ForegroundColor White
Write-Host "Старші:  $DaysOld днів (до $($cutoffDate.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor White
if ($WhatIf) {
    Write-Host "Режим:   WhatIf (без видалення)" -ForegroundColor Yellow
}
Write-Host ""

try {
    $files = Get-ChildItem -Path $Path -Filter $Filter -File -Recurse -ErrorAction Stop |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати список файлів: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Cleanup-OldFiles: Помилка сканування '$Path': $($_.Exception.Message)" -Level ERROR
    exit 1
}

if (-not $files) {
    Write-Host "Файлів для видалення не знайдено." -ForegroundColor Green
    Write-TkLog "Cleanup-OldFiles: Файлів для видалення не знайдено у '$Path'" -Level INFO
    exit 0
}

$totalSize = ($files | Measure-Object -Property Length -Sum).Sum
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)
$fileCount = @($files).Count

if ($WhatIf) {
    Write-Host "Файли, які було б видалено:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($file in $files) {
        $sizeMB = [math]::Round($file.Length / 1MB, 2)
        $line = "  {0,-60} {1,10} МБ  {2}" -f $file.FullName, $sizeMB, $file.LastWriteTime.ToString('yyyy-MM-dd')
        Write-Host $line -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Підсумок (WhatIf):" -ForegroundColor Yellow
    Write-Host "  Файлів:        $fileCount" -ForegroundColor Yellow
    Write-Host "  Загальний розмір: $totalSizeMB МБ" -ForegroundColor Yellow
    Write-TkLog "Cleanup-OldFiles: WhatIf - знайдено $fileCount файл(ів), $totalSizeMB МБ у '$Path'" -Level INFO
} else {
    $deletedCount = 0
    $deletedSize = 0
    $errorCount = 0

    foreach ($file in $files) {
        try {
            $fileSize = $file.Length
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $deletedCount++
            $deletedSize += $fileSize
            Write-Host "  Видалено: $($file.FullName)" -ForegroundColor Green
        } catch {
            $errorCount++
            Write-Host "  [ПОМИЛКА] $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Cleanup-OldFiles: Не вдалося видалити '$($file.FullName)': $($_.Exception.Message)" -Level ERROR
        }
    }

    $deletedSizeMB = [math]::Round($deletedSize / 1MB, 2)

    Write-Host ""
    Write-Host "Підсумок видалення:" -ForegroundColor Cyan
    Write-Host "  Видалено файлів:  $deletedCount з $fileCount" -ForegroundColor Green
    Write-Host "  Звільнено місця:  $deletedSizeMB МБ" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Host "  Помилок:          $errorCount" -ForegroundColor Red
    }
    Write-TkLog "Cleanup-OldFiles: Видалено $deletedCount/$fileCount файл(ів), звільнено $deletedSizeMB МБ у '$Path'" -Level INFO
}
