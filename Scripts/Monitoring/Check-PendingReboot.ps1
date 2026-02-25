<#
.SYNOPSIS
    Перевіряє чи потребує комп'ютер перезавантаження.
.DESCRIPTION
    Комплексна перевірка кількох індикаторів очікуваного перезавантаження:
    - Windows Update: ключ реєстру RebootRequired
    - CBS (Component Based Servicing): ключ реєстру RebootPending
    - PendingFileRenameOperations: заплановані операції перейменування файлів
    - SCCM Client: перевірка через WMI/CIM (якщо встановлено)
    Виводить кольоровий підсумок: зелений (перезавантаження не потрібне),
    червоний (перезавантаження потрібне) з деталями по кожній перевірці.
.PARAMETER ComputerName
    Ім'я комп'ютера для перевірки. За замовчуванням: локальний комп'ютер ($env:COMPUTERNAME).
.EXAMPLE
    .\Check-PendingReboot.ps1
    Перевіряє локальний комп'ютер на необхідність перезавантаження.
.EXAMPLE
    .\Check-PendingReboot.ps1 -ComputerName "SRV-DC01"
    Перевіряє віддалений комп'ютер SRV-DC01 на необхідність перезавантаження.
#>
param(
    [string]$ComputerName = $env:COMPUTERNAME
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск Check-PendingReboot для '$ComputerName'" -Level INFO

try {
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "     ПЕРЕВIРКА НЕОБХIДНОСТI ПЕРЕЗАВАНТАЖЕННЯ" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Комп'ютер:  $ComputerName" -ForegroundColor Cyan
    Write-Host "Дата:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "=====================================================`n" -ForegroundColor Cyan

    $isLocal = ($ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq 'localhost' -or $ComputerName -eq '.')
    $rebootNeeded = $false
    $checks = @()

    # -------------------------------------------------------
    #  Перевірка 1: Windows Update RebootRequired
    # -------------------------------------------------------
    Write-Host "  [1/4] Windows Update RebootRequired..." -ForegroundColor White -NoNewline
    try {
        if ($isLocal) {
            $wuRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
            $wuReboot = Test-Path $wuRegPath
        } else {
            $wuReboot = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
            } -ErrorAction Stop
        }

        if ($wuReboot) {
            $rebootNeeded = $true
            Write-Host " ТАК" -ForegroundColor Red
            Write-TkLog "Check-PendingReboot: $ComputerName - Windows Update RebootRequired = True" -Level WARN
        } else {
            Write-Host " Ні" -ForegroundColor Green
        }
        $checks += [pscustomobject]@{
            Перевірка  = 'Windows Update RebootRequired'
            Результат  = if ($wuReboot) { 'Так' } else { 'Ні' }
            Статус     = if ($wuReboot) { 'ПОТРIБНЕ' } else { 'OK' }
        }
    } catch {
        Write-Host " Помилка" -ForegroundColor DarkYellow
        Write-TkLog "WU check error: $($_.Exception.Message)" -Level WARN
        $checks += [pscustomobject]@{
            Перевірка  = 'Windows Update RebootRequired'
            Результат  = "Помилка: $($_.Exception.Message)"
            Статус     = 'N/A'
        }
    }

    # -------------------------------------------------------
    #  Перевірка 2: CBS (Component Based Servicing) RebootPending
    # -------------------------------------------------------
    Write-Host "  [2/4] CBS RebootPending..." -ForegroundColor White -NoNewline
    try {
        if ($isLocal) {
            $cbsRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
            $cbsReboot = Test-Path $cbsRegPath
        } else {
            $cbsReboot = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
            } -ErrorAction Stop
        }

        if ($cbsReboot) {
            $rebootNeeded = $true
            Write-Host " ТАК" -ForegroundColor Red
            Write-TkLog "Check-PendingReboot: $ComputerName - CBS RebootPending = True" -Level WARN
        } else {
            Write-Host " Ні" -ForegroundColor Green
        }
        $checks += [pscustomobject]@{
            Перевірка  = 'CBS RebootPending'
            Результат  = if ($cbsReboot) { 'Так' } else { 'Ні' }
            Статус     = if ($cbsReboot) { 'ПОТРIБНЕ' } else { 'OK' }
        }
    } catch {
        Write-Host " Помилка" -ForegroundColor DarkYellow
        Write-TkLog "CBS check error: $($_.Exception.Message)" -Level WARN
        $checks += [pscustomobject]@{
            Перевірка  = 'CBS RebootPending'
            Результат  = "Помилка: $($_.Exception.Message)"
            Статус     = 'N/A'
        }
    }

    # -------------------------------------------------------
    #  Перевірка 3: PendingFileRenameOperations
    # -------------------------------------------------------
    Write-Host "  [3/4] PendingFileRenameOperations..." -ForegroundColor White -NoNewline
    try {
        if ($isLocal) {
            $pfrRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            $pfrValue = (Get-ItemProperty -Path $pfrRegPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
            $pfrReboot = ($null -ne $pfrValue -and @($pfrValue).Count -gt 0)
        } else {
            $pfrReboot = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                $pfrRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                $pfrValue = (Get-ItemProperty -Path $pfrRegPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
                return ($null -ne $pfrValue -and @($pfrValue).Count -gt 0)
            } -ErrorAction Stop
        }

        if ($pfrReboot) {
            $rebootNeeded = $true
            Write-Host " ТАК" -ForegroundColor Red
            Write-TkLog "Check-PendingReboot: $ComputerName - PendingFileRenameOperations = True" -Level WARN
        } else {
            Write-Host " Ні" -ForegroundColor Green
        }
        $checks += [pscustomobject]@{
            Перевірка  = 'PendingFileRenameOperations'
            Результат  = if ($pfrReboot) { 'Так' } else { 'Ні' }
            Статус     = if ($pfrReboot) { 'ПОТРIБНЕ' } else { 'OK' }
        }
    } catch {
        Write-Host " Помилка" -ForegroundColor DarkYellow
        Write-TkLog "PFR check error: $($_.Exception.Message)" -Level WARN
        $checks += [pscustomobject]@{
            Перевірка  = 'PendingFileRenameOperations'
            Результат  = "Помилка: $($_.Exception.Message)"
            Статус     = 'N/A'
        }
    }

    # -------------------------------------------------------
    #  Перевірка 4: SCCM Client (якщо встановлено)
    # -------------------------------------------------------
    Write-Host "  [4/4] SCCM Client..." -ForegroundColor White -NoNewline
    try {
        if ($isLocal) {
            $sccmResult = Invoke-CimMethod -Namespace "root\ccm\ClientSDK" `
                -ClassName CCM_ClientUtilities `
                -MethodName DetermineIfRebootPending `
                -ErrorAction Stop
            $sccmReboot = ($null -ne $sccmResult -and $sccmResult.RebootPending)
        } else {
            $sccmReboot = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                try {
                    $result = Invoke-CimMethod -Namespace "root\ccm\ClientSDK" `
                        -ClassName CCM_ClientUtilities `
                        -MethodName DetermineIfRebootPending `
                        -ErrorAction Stop
                    return ($null -ne $result -and $result.RebootPending)
                } catch {
                    return $null
                }
            } -ErrorAction Stop
        }

        if ($null -eq $sccmReboot) {
            Write-Host " Не встановлено" -ForegroundColor DarkGray
            $checks += [pscustomobject]@{
                Перевірка  = 'SCCM Client'
                Результат  = 'Не встановлено'
                Статус     = 'N/A'
            }
        } elseif ($sccmReboot) {
            $rebootNeeded = $true
            Write-Host " ТАК" -ForegroundColor Red
            Write-TkLog "Check-PendingReboot: $ComputerName - SCCM RebootPending = True" -Level WARN
            $checks += [pscustomobject]@{
                Перевірка  = 'SCCM Client'
                Результат  = 'Так'
                Статус     = 'ПОТРIБНЕ'
            }
        } else {
            Write-Host " Ні" -ForegroundColor Green
            $checks += [pscustomobject]@{
                Перевірка  = 'SCCM Client'
                Результат  = 'Ні'
                Статус     = 'OK'
            }
        }
    } catch {
        Write-Host " Не встановлено" -ForegroundColor DarkGray
        $checks += [pscustomobject]@{
            Перевірка  = 'SCCM Client'
            Результат  = 'Не встановлено / Недоступно'
            Статус     = 'N/A'
        }
    }

    # -------------------------------------------------------
    #  Аптайм системи
    # -------------------------------------------------------
    Write-Host ""
    try {
        if ($isLocal) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
        }
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeDays = [math]::Floor($uptime.TotalDays)
        $uptimeStr = "{0} днів {1:hh\:mm\:ss}" -f $uptimeDays, $uptime
        $uptimeColor = if ($uptimeDays -gt 30) { 'Yellow' } elseif ($uptimeDays -gt 90) { 'Red' } else { 'Cyan' }
        Write-Host "  Аптайм:         $uptimeStr" -ForegroundColor $uptimeColor
        Write-Host "  Останній старт: $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
    } catch {
        Write-Host "  Аптайм:         не вдалося визначити" -ForegroundColor DarkGray
    }

    # -------------------------------------------------------
    #  Підсумок
    # -------------------------------------------------------
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                     РЕЗУЛЬТАТ" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    $checks | Format-Table -AutoSize

    if ($rebootNeeded) {
        Write-Host "ПЕРЕЗАВАНТАЖЕННЯ ПОТРIБНЕ" -ForegroundColor Red
        Write-TkLog "Check-PendingReboot: $ComputerName - перезавантаження ПОТРIБНЕ" -Level WARN
    } else {
        Write-Host "Перезавантаження НЕ потрібне" -ForegroundColor Green
        Write-TkLog "Check-PendingReboot: $ComputerName - перезавантаження не потрібне" -Level INFO
    }

} catch {
    $errMsg = "Критична помилка Check-PendingReboot: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
