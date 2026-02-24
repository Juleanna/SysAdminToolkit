<#
.SYNOPSIS
    Показує SMART-статус фізичних дисків системи.

.DESCRIPTION
    Використовує Get-PhysicalDisk для отримання інформації про фізичні диски:
    FriendlyName, MediaType, Size (ГБ), HealthStatus, OperationalStatus.
    Диски зі статусом "Healthy" виділяються зеленим, всі інші - червоним.

.EXAMPLE
    .\Disk-Health.ps1
    Виводить таблицю стану всіх фізичних дисків.
#>

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SMART-статус фізичних дисків" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    $disks = Get-PhysicalDisk -ErrorAction Stop
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати дані фізичних дисків: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Disk-Health: Не вдалося отримати дані фізичних дисків: $($_.Exception.Message)" -Level ERROR
    exit 1
}

if (-not $disks) {
    Write-Host "Фізичних дисків не знайдено." -ForegroundColor Yellow
    exit 0
}

# Заголовок таблиці
$header = "{0,-30} {1,-12} {2,10} {3,-15} {4,-20}" -f "Назва", "Тип", "Розмір ГБ", "Стан здоров'я", "Операційний статус"
Write-Host $header -ForegroundColor White
Write-Host ("-" * 90) -ForegroundColor Gray

foreach ($disk in $disks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
    $health = $disk.HealthStatus
    $operational = $disk.OperationalStatus
    $mediaType = if ($disk.MediaType) { $disk.MediaType } else { "Невідомо" }

    $line = "{0,-30} {1,-12} {2,10} {3,-15} {4,-20}" -f $disk.FriendlyName, $mediaType, $sizeGB, $health, $operational

    if ($health -eq "Healthy") {
        Write-Host $line -ForegroundColor Green
    } else {
        Write-Host $line -ForegroundColor Red
        Write-TkLog "Disk-Health: Диск '$($disk.FriendlyName)' має статус '$health'" -Level WARN
    }
}

Write-Host ""
Write-Host "Перевірку завершено. Всього дисків: $($disks.Count)" -ForegroundColor Cyan
Write-TkLog "Disk-Health: Перевірено $($disks.Count) диск(ів)" -Level INFO
