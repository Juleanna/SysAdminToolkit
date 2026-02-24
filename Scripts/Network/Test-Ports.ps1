<#
.SYNOPSIS
    Перевіряє доступність TCP-портів на вказаному комп'ютері.
.DESCRIPTION
    Для кожного порту створює TCP-з'єднання через System.Net.Sockets.TcpClient
    з обмеженням часу очікування (з конфігурації RemoteTimeoutSec).
    Виводить статус порту (Відкритий/Закритий) та час відповіді у мілісекундах.
    Відкриті порти виділяються зеленим кольором, закриті — червоним.
.PARAMETER ComputerName
    Ім'я хоста або IP-адреса для перевірки. Обов'язковий параметр.
.PARAMETER Ports
    Масив TCP-портів для перевірки. За замовчуванням: 22, 80, 443, 3389, 5985.
.EXAMPLE
    .\Test-Ports.ps1 -ComputerName "192.168.1.1"
    Перевіряє порти за замовчуванням (22, 80, 443, 3389, 5985) на вказаному хості.
.EXAMPLE
    .\Test-Ports.ps1 -ComputerName "server01" -Ports @(80, 443, 8080)
    Перевіряє лише порти 80, 443 та 8080 на сервері server01.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerName,

    [int[]]$Ports = @(22, 80, 443, 3389, 5985)
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск перевірки портів на хості '$ComputerName': $($Ports -join ', ')" -Level INFO

$cfg = Get-ToolkitConfig
$timeoutMs = if ($cfg.RemoteTimeoutSec) { $cfg.RemoteTimeoutSec * 1000 } else { 30000 }

Write-Host "`n=== Перевірка TCP-портів: $ComputerName ===" -ForegroundColor Cyan
Write-Host "Таймаут: $($timeoutMs / 1000) сек.`n" -ForegroundColor Cyan

$results = @()

foreach ($port in $Ports) {
    $status       = "Закритий"
    $responseTime = "-"
    $tcpClient    = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $connectTask = $tcpClient.ConnectAsync($ComputerName, $port)
        $completed = $connectTask.Wait($timeoutMs)
        $stopwatch.Stop()

        if ($completed -and $tcpClient.Connected) {
            $status       = "Відкритий"
            $responseTime = "$($stopwatch.ElapsedMilliseconds) мс"
        } else {
            $status       = "Закритий"
            $responseTime = "Таймаут"
        }
    } catch {
        $status       = "Закритий"
        $responseTime = "Помилка"
        Write-TkLog "Помилка підключення до ${ComputerName}:${port} — $($_.Exception.Message)" -Level DEBUG
    } finally {
        if ($tcpClient) {
            try { $tcpClient.Close() } catch {}
            try { $tcpClient.Dispose() } catch {}
        }
    }

    $obj = [pscustomobject]@{
        Port           = $port
        Status         = $status
        ResponseTimeMs = $responseTime
    }
    $results += $obj

    $color = if ($status -eq "Відкритий") { "Green" } else { "Red" }
    $line = "  Порт {0,-6} {1,-12} Час відповіді: {2}" -f $port, $status, $responseTime
    Write-Host $line -ForegroundColor $color
}

# Підсумок
$openCount   = ($results | Where-Object { $_.Status -eq "Відкритий" }).Count
$closedCount = ($results | Where-Object { $_.Status -ne "Відкритий" }).Count

Write-Host "`n--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Всього портів: $($results.Count) | " -NoNewline
Write-Host "Відкритих: $openCount" -ForegroundColor Green -NoNewline
Write-Host " | " -NoNewline
Write-Host "Закритих: $closedCount" -ForegroundColor Red

Write-TkLog "Перевірка портів '$ComputerName' завершена: відкритих=$openCount, закритих=$closedCount з $($results.Count)" -Level INFO
