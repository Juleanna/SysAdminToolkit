<#
.SYNOPSIS
    Виконує ручну трасировку маршруту до вказаного хоста.
.DESCRIPTION
    Реалізує traceroute вручну через System.Net.NetworkInformation.Ping
    з інкрементуванням TTL від 1 до MaxHops. Для кожного хопу відображає:
    номер хопу, IP-адресу, час відповіді та ім'я хоста (зворотний DNS).
    Кольорове кодування: зелений (<50мс), жовтий (<200мс), червоний (>200мс).
.PARAMETER Target
    Цільовий хост (IP-адреса або доменне ім'я) для трасировки.
    Обов'язковий параметр.
.PARAMETER MaxHops
    Максимальна кількість хопів. За замовчуванням: 30.
.EXAMPLE
    .\Trace-Route.ps1 -Target google.com
    Трасировка до google.com з максимумом 30 хопів.
.EXAMPLE
    .\Trace-Route.ps1 -Target 192.168.1.1 -MaxHops 15
    Трасировка до 192.168.1.1 з максимумом 15 хопів.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Target,

    [int]$MaxHops = 30
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск Trace-Route до '$Target' (MaxHops=$MaxHops)" -Level INFO

try {
    # --- Розв'язання DNS для цілі ---
    $targetIP = $null
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($resolved) {
            $targetIP = $resolved.IPAddressToString
        } else {
            Write-Host "Не вдалося розв'язати '$Target' в IPv4-адресу." -ForegroundColor Red
            Write-TkLog "DNS resolve failed для '$Target'" -Level ERROR
            exit 1
        }
    } catch {
        Write-Host "Помилка DNS-розв'язання для '$Target': $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "DNS error: $($_.Exception.Message)" -Level ERROR
        exit 1
    }

    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "         ТРАСИРОВКА МАРШРУТУ" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Ціль:       $Target ($targetIP)" -ForegroundColor Cyan
    Write-Host "Макс. хопів: $MaxHops" -ForegroundColor Cyan
    Write-Host "=====================================================`n" -ForegroundColor Cyan

    $headerLine = "{0,-5} {1,-18} {2,-10} {3}" -f "Хоп", "IP-адреса", "Час (мс)", "Ім'я хоста"
    Write-Host $headerLine -ForegroundColor White
    Write-Host ("-" * 70) -ForegroundColor DarkGray

    $ping = New-Object System.Net.NetworkInformation.Ping
    $buffer = [byte[]]::new(32)
    $timeout = 3000  # 3 секунди таймаут

    $reached = $false

    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        try {
            $options = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
            $reply = $ping.Send($targetIP, $timeout, $buffer, $options)

            $hopIP = if ($reply.Address) { $reply.Address.IPAddressToString } else { '*' }
            $hopTime = if ($reply.Status -eq 'Success' -or $reply.Status -eq 'TtlExpired') {
                $reply.RoundtripTime
            } else {
                -1
            }

            # --- Зворотний DNS ---
            $hostname = '*'
            if ($hopIP -ne '*') {
                try {
                    $dnsResult = [System.Net.Dns]::GetHostEntry($hopIP)
                    $hostname = $dnsResult.HostName
                } catch {
                    $hostname = '-'
                }
            }

            # --- Кольорове кодування за часом ---
            if ($hopTime -lt 0) {
                $timeStr = '*'
                $color = 'DarkGray'
            } elseif ($hopTime -lt 50) {
                $timeStr = "$hopTime мс"
                $color = 'Green'
            } elseif ($hopTime -lt 200) {
                $timeStr = "$hopTime мс"
                $color = 'Yellow'
            } else {
                $timeStr = "$hopTime мс"
                $color = 'Red'
            }

            if ($reply.Status -eq 'TimedOut') {
                $line = "{0,-5} {1,-18} {2,-10} {3}" -f $ttl, '*', '*', 'Таймаут'
                Write-Host $line -ForegroundColor DarkGray
            } else {
                $line = "{0,-5} {1,-18} {2,-10} {3}" -f $ttl, $hopIP, $timeStr, $hostname
                Write-Host $line -ForegroundColor $color
            }

            # --- Перевірка досягнення цілі ---
            if ($reply.Status -eq 'Success') {
                $reached = $true
                break
            }

        } catch {
            $line = "{0,-5} {1,-18} {2,-10} {3}" -f $ttl, '*', '*', "Помилка: $($_.Exception.Message)"
            Write-Host $line -ForegroundColor Red
            Write-TkLog "Trace-Route хоп $ttl помилка: $($_.Exception.Message)" -Level WARN
        }
    }

    $ping.Dispose()

    # --- Підсумок ---
    Write-Host "`n--- Підсумок ---" -ForegroundColor Cyan
    if ($reached) {
        Write-Host "Ціль $Target ($targetIP) досягнута за $ttl хоп(ів)." -ForegroundColor Green
        Write-TkLog "Trace-Route до '$Target' завершено за $ttl хопів" -Level INFO
    } else {
        Write-Host "Ціль $Target ($targetIP) не досягнута за $MaxHops хопів." -ForegroundColor Red
        Write-TkLog "Trace-Route до '$Target' не завершено за $MaxHops хопів" -Level WARN
    }

} catch {
    $errMsg = "Критична помилка Trace-Route: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
