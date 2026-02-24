<#
.SYNOPSIS
    Дашборд стану критичних служб Windows.

.DESCRIPTION
    Зчитує список критичних служб з ToolkitConfig.json (CriticalServices)
    та відображає їх поточний стан: ім'я, відображуване ім'я, статус, тип запуску.
    Зупинені служби підсвічуються червоним, запущені — зеленим.
    Підтримує перевірку на віддаленому комп'ютері.

.PARAMETER ComputerName
    Ім'я або IP-адреса віддаленого комп'ютера.
    Якщо не вказано, перевіряються служби на локальній машині.

.EXAMPLE
    .\Service-Monitor.ps1
    Показує стан критичних служб на локальному комп'ютері.

.EXAMPLE
    .\Service-Monitor.ps1 -ComputerName "SERVER01"
    Показує стан критичних служб на віддаленому комп'ютері SERVER01.
#>

param(
    [string]$ComputerName
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

try {
    $cfg = Get-ToolkitConfig
    $criticalServices = $cfg.CriticalServices

    if (-not $criticalServices -or $criticalServices.Count -eq 0) {
        Write-Host "У конфігурації не знайдено жодної критичної служби (CriticalServices)." -ForegroundColor Yellow
        exit 0
    }

    $targetName = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
    $isRemote = [bool]$ComputerName

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Моніторинг критичних служб — $targetName" -ForegroundColor Cyan
    Write-Host "  Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($isRemote) {
        if (-not (Test-ComputerOnline -ComputerName $ComputerName)) {
            Write-Host "Комп'ютер '$ComputerName' недоступний у мережі." -ForegroundColor Red
            Write-TkLog "Service-Monitor: комп'ютер '$ComputerName' недоступний." -Level ERROR
            exit 1
        }
        Write-Host "Підключення до віддаленого комп'ютера '$ComputerName'..." -ForegroundColor Gray
    }

    $results = @()
    $stoppedCount = 0
    $runningCount = 0
    $notFoundCount = 0

    foreach ($svcName in $criticalServices) {
        try {
            $getParams = @{ Name = $svcName; ErrorAction = 'Stop' }
            if ($isRemote) { $getParams.ComputerName = $ComputerName }

            $svc = Get-Service @getParams

            $startType = "N/A"
            try {
                if ($isRemote) {
                    $wmiSvc = Get-WmiObject -Class Win32_Service -ComputerName $ComputerName -Filter "Name='$svcName'" -ErrorAction Stop
                    $startType = $wmiSvc.StartMode
                } else {
                    $startType = (Get-Service -Name $svcName | Select-Object -ExpandProperty StartType).ToString()
                }
            } catch {
                $startType = "N/A"
            }

            $statusText = $svc.Status.ToString()
            $color = switch ($svc.Status) {
                'Running' { 'Green' }
                'Stopped' { 'Red' }
                default   { 'Yellow' }
            }

            if ($svc.Status -eq 'Running') { $runningCount++ } else { $stoppedCount++ }

            $results += [pscustomobject]@{
                Name        = $svc.ServiceName
                DisplayName = $svc.DisplayName
                Status      = $statusText
                StartType   = $startType
                Color       = $color
            }
        } catch {
            $notFoundCount++
            $results += [pscustomobject]@{
                Name        = $svcName
                DisplayName = "(не знайдено)"
                Status      = "Не знайдено"
                StartType   = "N/A"
                Color       = 'DarkGray'
            }
        }
    }

    # Виведення таблиці
    $nameWidth = 20
    $displayWidth = 35
    $statusWidth = 14
    $startWidth = 14

    $header = "{0,-$nameWidth} {1,-$displayWidth} {2,-$statusWidth} {3,-$startWidth}" -f "Ім'я", "Відображуване ім'я", "Статус", "Тип запуску"
    Write-Host $header -ForegroundColor White
    Write-Host ("-" * ($nameWidth + $displayWidth + $statusWidth + $startWidth + 3)) -ForegroundColor DarkGray

    foreach ($r in $results) {
        $displayName = if ($r.DisplayName.Length -gt ($displayWidth - 2)) {
            $r.DisplayName.Substring(0, $displayWidth - 5) + "..."
        } else {
            $r.DisplayName
        }

        $line = "{0,-$nameWidth} {1,-$displayWidth} {2,-$statusWidth} {3,-$startWidth}" -f $r.Name, $displayName, $r.Status, $r.StartType
        Write-Host $line -ForegroundColor $r.Color
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("  Всього: {0} | Працюють: {1} | Зупинені: {2} | Не знайдено: {3}" -f $criticalServices.Count, $runningCount, $stoppedCount, $notFoundCount) -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($stoppedCount -gt 0) {
        Write-Host ""
        Write-Host "  УВАГА: $stoppedCount критичних служб зупинено!" -ForegroundColor Red
        Write-TkLog "Service-Monitor: $stoppedCount критичних служб зупинено на $targetName." -Level WARN
    }

    Write-TkLog "Service-Monitor: перевірено $($criticalServices.Count) служб на $targetName (працюють: $runningCount, зупинені: $stoppedCount)." -Level INFO

} catch {
    Write-Host "Помилка під час моніторингу служб: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Service-Monitor: критична помилка — $($_.Exception.Message)" -Level ERROR
    exit 1
}
