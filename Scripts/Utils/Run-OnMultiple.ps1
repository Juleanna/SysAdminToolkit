<#
.SYNOPSIS
    Виконує скрипт на декількох комп'ютерах зі списку Hosts.json.

.DESCRIPTION
    Завантажує список хостів за допомогою Get-TkHostsList, за потреби фільтрує
    за роллю (-Role), перевіряє доступність кожного комп'ютера через
    Test-ComputerOnline і виконує вказаний скрипт на доступних хостах через
    Invoke-Command -ComputerName. При використанні параметра -Parallel запускає
    команди як фонові завдання (-AsJob) для паралельного виконання.
    По завершенні виводить підсумок: успіх/помилка для кожного хоста.

.PARAMETER ScriptPath
    Шлях до PowerShell-скрипта для виконання на віддалених комп'ютерах (обов'язковий).

.PARAMETER Role
    Фільтр за роллю з Hosts.json (наприклад, Workstation, Server).
    Якщо не вказано, скрипт виконується на всіх хостах.

.PARAMETER Parallel
    Якщо вказано, команди виконуються паралельно через Invoke-Command -AsJob.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath "D:\SysAdminToolkit\Scripts\Utils\Clean-Temp.ps1"
    Виконує Clean-Temp.ps1 на всіх комп'ютерах зі списку.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath ".\Check-Disk.ps1" -Role "Server"
    Виконує скрипт тільки на хостах з роллю Server.

.EXAMPLE
    .\Run-OnMultiple.ps1 -ScriptPath ".\Clean-Temp.ps1" -Parallel
    Виконує скрипт на всіх хостах паралельно (через -AsJob).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,

    [string]$Role,

    [switch]$Parallel
)

Import-Module "$PSScriptRoot\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig

Write-TkLog "Run-OnMultiple: запуск скрипта '$ScriptPath' на декількох комп'ютерах" -Level INFO

# Перевірка існування скрипта
if (-not (Test-Path $ScriptPath)) {
    Write-Host "[ПОМИЛКА] Скрипт не знайдено: $ScriptPath" -ForegroundColor Red
    Write-TkLog "Run-OnMultiple: скрипт не знайдено: $ScriptPath" -Level ERROR
    exit 1
}

$scriptFullPath = (Resolve-Path $ScriptPath).Path
$scriptContent = Get-Content -Path $scriptFullPath -Raw -Encoding UTF8

# Завантаження списку хостів
$hosts = Get-TkHostsList

if (-not $hosts -or $hosts.Count -eq 0) {
    Write-Host "[ПОМИЛКА] Список хостів порожній. Перевірте Config/Hosts.json." -ForegroundColor Red
    Write-TkLog "Run-OnMultiple: список хостів порожній" -Level ERROR
    exit 1
}

# Фільтрація за роллю
if ($Role) {
    $hosts = $hosts | Where-Object { $_.Role -eq $Role }
    if (-not $hosts -or $hosts.Count -eq 0) {
        Write-Host "[ПОМИЛКА] Хостів з роллю '$Role' не знайдено." -ForegroundColor Yellow
        Write-TkLog "Run-OnMultiple: хостів з роллю '$Role' не знайдено" -Level WARN
        exit 0
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Виконання скрипта на декількох комп'ютерах" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Скрипт:     $scriptFullPath" -ForegroundColor White
if ($Role) {
    Write-Host "  Роль:       $Role" -ForegroundColor White
}
Write-Host "  Хостів:     $($hosts.Count)" -ForegroundColor White
Write-Host "  Паралельно: $(if ($Parallel) { 'Так' } else { 'Ні' })" -ForegroundColor White
Write-Host "  Дата:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0
$offlineCount = 0
$results = @()
$timeoutSec = if ($cfg.RemoteTimeoutSec) { $cfg.RemoteTimeoutSec } else { 30 }

$scriptBlock = [ScriptBlock]::Create($scriptContent)

if ($Parallel) {
    # --- Паралельний режим (AsJob) ---
    Write-Host "Запуск у паралельному режимі..." -ForegroundColor Gray
    Write-Host ""

    $jobs = @()

    foreach ($hostEntry in $hosts) {
        $computerName = if ($hostEntry.IP) { $hostEntry.IP } else { $hostEntry.Name }
        $displayName = "$($hostEntry.Name) ($computerName)"

        # Перевірка доступності
        if (-not (Test-ComputerOnline -ComputerName $computerName -TimeoutMs ($timeoutSec * 1000))) {
            Write-Host "  [ОФЛАЙН]  $displayName" -ForegroundColor DarkGray
            Write-TkLog "Run-OnMultiple: хост '$displayName' недоступний" -Level WARN
            $offlineCount++
            $results += [pscustomobject]@{ Хост = $displayName; Статус = "Офлайн"; Деталі = "Комп'ютер недоступний" }
            continue
        }

        Write-Host "  [ЗАПУСК]  $displayName — запуск завдання..." -ForegroundColor Gray

        try {
            $job = Invoke-Command -ComputerName $computerName -ScriptBlock $scriptBlock -AsJob -ErrorAction Stop
            $jobs += [pscustomobject]@{
                Job         = $job
                HostEntry   = $hostEntry
                DisplayName = $displayName
                ComputerName = $computerName
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $displayName — не вдалося запустити: $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Run-OnMultiple: помилка запуску на '$displayName': $($_.Exception.Message)" -Level ERROR
            $failCount++
            $results += [pscustomobject]@{ Хост = $displayName; Статус = "Помилка"; Деталі = $_.Exception.Message }
        }
    }

    # Очікування завершення завдань
    if ($jobs.Count -gt 0) {
        Write-Host ""
        Write-Host "  Очікування завершення $($jobs.Count) завдань..." -ForegroundColor Gray

        foreach ($jobInfo in $jobs) {
            try {
                $jobResult = $jobInfo.Job | Wait-Job -Timeout ($timeoutSec * 2) | Receive-Job -ErrorAction Stop
                Write-Host "  [OK]      $($jobInfo.DisplayName)" -ForegroundColor Green
                $successCount++
                $results += [pscustomobject]@{ Хост = $jobInfo.DisplayName; Статус = "Успіх"; Деталі = "Виконано" }
            } catch {
                Write-Host "  [ПОМИЛКА] $($jobInfo.DisplayName) — $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Run-OnMultiple: помилка на '$($jobInfo.DisplayName)': $($_.Exception.Message)" -Level ERROR
                $failCount++
                $results += [pscustomobject]@{ Хост = $jobInfo.DisplayName; Статус = "Помилка"; Деталі = $_.Exception.Message }
            } finally {
                $jobInfo.Job | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    # --- Послідовний режим ---
    Write-Host "Запуск у послідовному режимі..." -ForegroundColor Gray
    Write-Host ""

    foreach ($hostEntry in $hosts) {
        $computerName = if ($hostEntry.IP) { $hostEntry.IP } else { $hostEntry.Name }
        $displayName = "$($hostEntry.Name) ($computerName)"

        # Перевірка доступності
        Write-Host "  Перевірка $displayName..." -NoNewline -ForegroundColor Gray

        if (-not (Test-ComputerOnline -ComputerName $computerName -TimeoutMs ($timeoutSec * 1000))) {
            Write-Host " ОФЛАЙН" -ForegroundColor DarkGray
            Write-TkLog "Run-OnMultiple: хост '$displayName' недоступний" -Level WARN
            $offlineCount++
            $results += [pscustomobject]@{ Хост = $displayName; Статус = "Офлайн"; Деталі = "Комп'ютер недоступний" }
            continue
        }

        Write-Host " онлайн" -ForegroundColor Green

        try {
            $output = Invoke-Command -ComputerName $computerName -ScriptBlock $scriptBlock -ErrorAction Stop
            Write-Host "  [OK]      $displayName" -ForegroundColor Green
            Write-TkLog "Run-OnMultiple: скрипт успішно виконано на '$displayName'" -Level INFO
            $successCount++
            $results += [pscustomobject]@{ Хост = $displayName; Статус = "Успіх"; Деталі = "Виконано" }
        } catch {
            Write-Host "  [ПОМИЛКА] $displayName — $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Run-OnMultiple: помилка на '$displayName': $($_.Exception.Message)" -Level ERROR
            $failCount++
            $results += [pscustomobject]@{ Хост = $displayName; Статус = "Помилка"; Деталі = $_.Exception.Message }
        }
    }
}

# --- Підсумок ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Підсумок виконання:" -ForegroundColor Cyan
Write-Host "  Всього хостів:   $($hosts.Count)" -ForegroundColor White
Write-Host "  Успішно:          $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Помилки:          $failCount" -ForegroundColor Red
}
if ($offlineCount -gt 0) {
    Write-Host "  Недоступні:       $offlineCount" -ForegroundColor DarkGray
}
Write-Host "============================================" -ForegroundColor Cyan

Write-TkLog "Run-OnMultiple: завершено. Успішно: $successCount, помилок: $failCount, недоступних: $offlineCount з $($hosts.Count)" -Level INFO
