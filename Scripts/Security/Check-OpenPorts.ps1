<#
.SYNOPSIS
    Показує відкриті TCP та UDP порти на локальній машині.

.DESCRIPTION
    Збирає інформацію про прослуховувані TCP/UDP з'єднання за допомогою
    Get-NetTCPConnection та Get-NetUDPEndpoint. Для кожного порту відображає
    локальний порт, стан, PID та ім'я процесу. Результати відсортовані за портом.

.PARAMETER TCPOnly
    Показати лише TCP-порти.

.PARAMETER UDPOnly
    Показати лише UDP-порти.

.EXAMPLE
    .\Check-OpenPorts.ps1
    Показує всі відкриті TCP та UDP порти.

.EXAMPLE
    .\Check-OpenPorts.ps1 -TCPOnly
    Показує лише TCP-порти у стані Listen.

.EXAMPLE
    .\Check-OpenPorts.ps1 -UDPOnly
    Показує лише UDP-порти.
#>

param(
    [switch]$TCPOnly,
    [switch]$UDPOnly
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск перевірки відкритих портів" -Level INFO

if ($TCPOnly -and $UDPOnly) {
    Write-Warning "Вказано одночасно -TCPOnly та -UDPOnly. Буде показано обидва протоколи."
    $TCPOnly = $false
    $UDPOnly = $false
}

# Кеш процесів для швидкого розв'язання PID -> ProcessName
$processCache = @{}
try {
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $processCache[$_.Id] = $_.ProcessName
    }
} catch {
    Write-TkLog "Не вдалося побудувати кеш процесів: $($_.Exception.Message)" -Level WARN
}

function Get-ProcessNameSafe {
    param([int]$Pid_)
    if ($Pid_ -eq 0) { return "System Idle" }
    if ($Pid_ -eq 4) { return "System" }
    if ($processCache.ContainsKey($Pid_)) { return $processCache[$Pid_] }
    try {
        return (Get-Process -Id $Pid_ -ErrorAction Stop).ProcessName
    } catch {
        return "N/A"
    }
}

$allResults = @()

# --- TCP ---
if (-not $UDPOnly) {
    Write-Host "`n  TCP-ПОРТИ (Listen)" -ForegroundColor Cyan
    Write-Host ("  " + "-" * 70) -ForegroundColor DarkGray

    try {
        $tcpConnections = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Sort-Object -Property LocalPort

        foreach ($conn in $tcpConnections) {
            $procName = Get-ProcessNameSafe -Pid_ $conn.OwningProcess
            $allResults += [pscustomobject]@{
                Protocol      = "TCP"
                LocalAddress  = $conn.LocalAddress
                LocalPort     = $conn.LocalPort
                State         = $conn.State
                PID           = $conn.OwningProcess
                ProcessName   = $procName
            }
        }

        $tcpResults = $allResults | Where-Object { $_.Protocol -eq "TCP" }
        if ($tcpResults) {
            $tcpResults | Format-Table -Property LocalPort, LocalAddress, State, PID, ProcessName -AutoSize
        } else {
            Write-Host "  TCP-портів у стані Listen не знайдено." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Не вдалося отримати TCP-з'єднання: $($_.Exception.Message)"
        Write-TkLog "Помилка отримання TCP: $($_.Exception.Message)" -Level ERROR
    }
}

# --- UDP ---
if (-not $TCPOnly) {
    Write-Host "`n  UDP-ПОРТИ" -ForegroundColor Cyan
    Write-Host ("  " + "-" * 70) -ForegroundColor DarkGray

    try {
        $udpEndpoints = Get-NetUDPEndpoint -ErrorAction Stop |
            Sort-Object -Property LocalPort

        foreach ($ep in $udpEndpoints) {
            $procName = Get-ProcessNameSafe -Pid_ $ep.OwningProcess
            $allResults += [pscustomobject]@{
                Protocol      = "UDP"
                LocalAddress  = $ep.LocalAddress
                LocalPort     = $ep.LocalPort
                State         = "N/A"
                PID           = $ep.OwningProcess
                ProcessName   = $procName
            }
        }

        $udpResults = $allResults | Where-Object { $_.Protocol -eq "UDP" }
        if ($udpResults) {
            $udpResults | Format-Table -Property LocalPort, LocalAddress, PID, ProcessName -AutoSize
        } else {
            Write-Host "  UDP-портів не знайдено." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Не вдалося отримати UDP-з'єднання: $($_.Exception.Message)"
        Write-TkLog "Помилка отримання UDP: $($_.Exception.Message)" -Level ERROR
    }
}

$totalPorts = @($allResults).Count
Write-Host ("  " + "-" * 70) -ForegroundColor DarkGray
Write-Host "  Всього портів: $totalPorts" -ForegroundColor Cyan
Write-TkLog "Перевірка портів завершена. Знайдено: $totalPorts" -Level INFO
