<#
.SYNOPSIS
    Перевіряє стан та час роботи критичних служб із конфігурації.
.DESCRIPTION
    Зчитує список критичних служб з ToolkitConfig.json (CriticalServices)
    та для кожної показує: Name, DisplayName, Status, StartType, ProcessId,
    StartTime (через Get-Process по PID) та Uptime (TimeSpan).
    Працюючі служби виділяються зеленим, зупинені — червоним.
    За допомогою перемикача -ExportHtml можна зберегти HTML-звіт.
.PARAMETER ExportHtml
    Якщо вказано, експортує результати у HTML-файл у папку Reports.
.EXAMPLE
    .\Check-ServiceUptime.ps1
    Перевіряє всі критичні служби з конфігурації та виводить результати в консоль.
.EXAMPLE
    .\Check-ServiceUptime.ps1 -ExportHtml
    Перевіряє критичні служби та зберігає HTML-звіт.
#>
param(
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск перевірки критичних служб" -Level INFO

$cfg = Get-ToolkitConfig
$serviceNames = $cfg.CriticalServices

if (-not $serviceNames -or $serviceNames.Count -eq 0) {
    Write-Host "Список критичних служб не налаштовано в конфігурації (CriticalServices)." -ForegroundColor Yellow
    Write-TkLog "CriticalServices порожній або відсутній у конфігурації" -Level WARN
    exit 0
}

Write-Host "`n=== Стан критичних служб ===" -ForegroundColor Cyan
Write-Host ""

$results = @()

foreach ($svcName in $serviceNames) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction Stop

        $processId = $null
        $startTime = $null
        $uptime    = $null

        if ($svc.Status -eq 'Running') {
            try {
                $wmiSvc = Get-CimInstance Win32_Service -Filter "Name='$svcName'" -ErrorAction Stop
                if ($wmiSvc -and $wmiSvc.ProcessId -gt 0) {
                    $processId = $wmiSvc.ProcessId
                    $process = Get-Process -Id $processId -ErrorAction Stop
                    if ($process.StartTime) {
                        $startTime = $process.StartTime
                        $uptimeSpan = (Get-Date) - $startTime
                        $uptime = "{0}д {1}г {2}хв" -f $uptimeSpan.Days, $uptimeSpan.Hours, $uptimeSpan.Minutes
                    }
                }
            } catch {
                $startTime = $null
                $uptime    = "Недоступно"
            }
        }

        $obj = [pscustomobject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.Status.ToString()
            StartType   = $svc.StartType.ToString()
            ProcessId   = if ($processId) { $processId } else { "-" }
            StartTime   = if ($startTime) { $startTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "-" }
            Uptime      = if ($uptime) { $uptime } else { "-" }
        }
        $results += $obj

        $color      = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
        $statusText = if ($svc.Status -eq 'Running') { "Працює" } else { "Зупинено" }

        $line = "{0,-20} {1,-30} {2,-12} {3,-14} PID: {4,-8} Старт: {5,-22} Аптайм: {6}" -f `
            $svc.Name, $svc.DisplayName, $statusText, $svc.StartType, $obj.ProcessId, $obj.StartTime, $obj.Uptime
        Write-Host $line -ForegroundColor $color

    } catch {
        $obj = [pscustomobject]@{
            Name        = $svcName
            DisplayName = "-"
            Status      = "Не знайдено"
            StartType   = "-"
            ProcessId   = "-"
            StartTime   = "-"
            Uptime      = "-"
        }
        $results += $obj
        Write-Host ("{0,-20} Служба не знайдена" -f $svcName) -ForegroundColor Red
        Write-TkLog "Служба '$svcName' не знайдена на цьому комп'ютері" -Level WARN
    }
}

# Підсумок
$running  = ($results | Where-Object { $_.Status -eq 'Running' }).Count
$stopped  = ($results | Where-Object { $_.Status -ne 'Running' -and $_.Status -ne 'Не знайдено' }).Count
$notFound = ($results | Where-Object { $_.Status -eq 'Не знайдено' }).Count

Write-Host "`n--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Всього: $($results.Count) | " -NoNewline
Write-Host "Працюють: $running" -ForegroundColor Green -NoNewline
Write-Host " | " -NoNewline
if ($stopped -gt 0) {
    Write-Host "Зупинено: $stopped" -ForegroundColor Red -NoNewline
} else {
    Write-Host "Зупинено: $stopped" -ForegroundColor Green -NoNewline
}
Write-Host " | " -NoNewline
if ($notFound -gt 0) {
    Write-Host "Не знайдено: $notFound" -ForegroundColor Red
} else {
    Write-Host "Не знайдено: $notFound" -ForegroundColor Green
}

Write-TkLog "Перевірка служб: всього=$($results.Count), працюють=$running, зупинено=$stopped, не знайдено=$notFound" -Level INFO

# Експорт HTML-звіту
if ($ExportHtml) {
    try {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportPath = Join-Path $reportDir "ServiceUptime_${env:COMPUTERNAME}_${timestamp}.html"
        $exportedPath = Export-TkReport -Data $results -Path $reportPath -Title "Стан критичних служб — $env:COMPUTERNAME" -Format HTML
        Write-Host "`nHTML-звіт збережено: $exportedPath" -ForegroundColor Green
        Write-TkLog "HTML-звіт критичних служб збережено: $exportedPath" -Level INFO
    } catch {
        Write-Host "Не вдалося зберегти HTML-звіт: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка збереження HTML-звіту служб: $($_.Exception.Message)" -Level ERROR
    }
}
