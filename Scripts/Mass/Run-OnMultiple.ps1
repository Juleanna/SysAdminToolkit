<#
.SYNOPSIS
    Виконує скрипт на кількох комп'ютерах з Hosts.json.

.DESCRIPTION
    Запускає вказаний PowerShell-скрипт на віддалених комп'ютерах через Invoke-Command
    з параметром -FilePath. Список комп'ютерів береться з Hosts.json або передається
    вручну. Підтримує паралельне виконання через runspaces (-Parallel).
    Показує результат OK/FAIL для кожного хоста.

.PARAMETER ScriptPath
    Шлях до PowerShell-скрипту для виконання (обов'язковий).

.PARAMETER ComputerNames
    Масив імен комп'ютерів. Якщо не вказано, завантажує всі з Config\Hosts.json.

.PARAMETER Parallel
    Увімкнути паралельне виконання через runspaces замість послідовного.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath "D:\SysAdminToolkit\Scripts\Utils\System-Info.ps1"
    Виконує скрипт на всіх комп'ютерах з Hosts.json послідовно.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath ".\myscript.ps1" -ComputerNames "PC-01","PC-02"
    Виконує скрипт на вказаних комп'ютерах.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath ".\myscript.ps1" -Parallel
    Виконує скрипт паралельно на всіх хостах з Hosts.json.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,

    [string[]]$ComputerNames,

    [switch]$Parallel
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск Run-OnMultiple: скрипт '$ScriptPath'" -Level INFO

# --- Перевірка скрипта ---
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Скрипт не знайдено: $ScriptPath"
    Write-TkLog "Скрипт не знайдено: $ScriptPath" -Level ERROR
    exit 1
}

$ScriptPath = (Resolve-Path $ScriptPath).Path

# --- Завантаження списку комп'ютерів ---
if (-not $ComputerNames -or $ComputerNames.Count -eq 0) {
    $hosts = Get-TkHostsList
    if (-not $hosts -or @($hosts).Count -eq 0) {
        Write-Error "Список комп'ютерів порожній. Перевірте Config\Hosts.json або вкажіть -ComputerNames."
        Write-TkLog "Порожній список комп'ютерів" -Level ERROR
        exit 1
    }
    $ComputerNames = $hosts | ForEach-Object {
        if ($_.IP) { $_.IP } elseif ($_.Name) { $_.Name } else { $null }
    } | Where-Object { $_ }
}

$totalHosts = @($ComputerNames).Count
Write-Host "Виконання скрипту на $totalHosts комп'ютерах..." -ForegroundColor Cyan
Write-Host "  Скрипт: $ScriptPath" -ForegroundColor Gray
Write-Host "  Режим:  $(if ($Parallel) { 'Паралельний' } else { 'Послідовний' })" -ForegroundColor Gray
Write-Host ""

$cfg = Get-ToolkitConfig
$timeout = $cfg.RemoteTimeoutSec

$results = @()

if ($Parallel) {
    # --- Паралельне виконання через runspaces ---
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min($totalHosts, 10))
    $runspacePool.Open()

    $jobs = @()

    foreach ($computer in $ComputerNames) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool

        [void]$ps.AddScript({
            param($Computer, $ScriptPath, $Timeout)
            try {
                $output = Invoke-Command -ComputerName $Computer -FilePath $ScriptPath `
                    -ErrorAction Stop
                return [pscustomobject]@{
                    Computer = $Computer
                    Status   = 'OK'
                    Output   = $output
                    Error    = $null
                }
            } catch {
                return [pscustomobject]@{
                    Computer = $Computer
                    Status   = 'FAIL'
                    Output   = $null
                    Error    = $_.Exception.Message
                }
            }
        })

        [void]$ps.AddArgument($computer)
        [void]$ps.AddArgument($ScriptPath)
        [void]$ps.AddArgument($timeout)

        $handle = $ps.BeginInvoke()
        $jobs += [pscustomobject]@{
            PowerShell = $ps
            Handle     = $handle
            Computer   = $computer
        }
    }

    # Очікування та збір результатів
    foreach ($job in $jobs) {
        try {
            $result = $job.PowerShell.EndInvoke($job.Handle)
            if ($result) {
                $results += $result
            } else {
                $results += [pscustomobject]@{
                    Computer = $job.Computer
                    Status   = 'FAIL'
                    Output   = $null
                    Error    = "Порожня відповідь"
                }
            }
        } catch {
            $results += [pscustomobject]@{
                Computer = $job.Computer
                Status   = 'FAIL'
                Output   = $null
                Error    = $_.Exception.Message
            }
        } finally {
            $job.PowerShell.Dispose()
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

} else {
    # --- Послідовне виконання ---
    foreach ($computer in $ComputerNames) {
        Write-Host "  $computer... " -NoNewline -ForegroundColor Gray
        try {
            $output = Invoke-Command -ComputerName $computer -FilePath $ScriptPath `
                -ErrorAction Stop
            Write-Host "OK" -ForegroundColor Green
            $results += [pscustomobject]@{
                Computer = $computer
                Status   = 'OK'
                Output   = $output
                Error    = $null
            }
        } catch {
            Write-Host "FAIL" -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkRed
            $results += [pscustomobject]@{
                Computer = $computer
                Status   = 'FAIL'
                Output   = $null
                Error    = $_.Exception.Message
            }
        }
    }
}

# --- Підсумок ---
if ($Parallel) {
    Write-Host "Результати:" -ForegroundColor Cyan
    foreach ($r in $results) {
        $color = if ($r.Status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  $($r.Computer): " -NoNewline -ForegroundColor Gray
        Write-Host $r.Status -ForegroundColor $color
        if ($r.Error) {
            Write-Host "    $($r.Error)" -ForegroundColor DarkRed
        }
    }
}

$okCount = @($results | Where-Object { $_.Status -eq 'OK' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count

Write-Host ""
Write-Host ("  " + "-" * 40) -ForegroundColor DarkGray
Write-Host "  Всього: $totalHosts  |  " -NoNewline -ForegroundColor Cyan
Write-Host "OK: $okCount" -NoNewline -ForegroundColor Green
Write-Host "  |  " -NoNewline -ForegroundColor Cyan
Write-Host "FAIL: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

Write-TkLog "Run-OnMultiple завершено. Скрипт: '$ScriptPath'. OK: $okCount, FAIL: $failCount" -Level INFO
