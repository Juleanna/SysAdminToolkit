param(
    [string]$Subnet,
    [int]$Timeout = 1000
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if (-not $Subnet) {
    $Subnet = (Get-ToolkitConfig).Subnet
}

Write-Host "Сканування підмережі ${Subnet}1-254 (таймаут ${Timeout}мс)..." -ForegroundColor Cyan

$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 50)
$runspacePool.Open()

$jobs = @()
$scriptBlock = {
    param($ip, $timeout)
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $ping.Send($ip, $timeout)
        if ($reply.Status -eq 'Success') {
            return [pscustomobject]@{ IP = $ip; Status = 'Online'; RTT = "$($reply.RoundtripTime)ms" }
        }
    } catch {} finally {
        $ping.Dispose()
    }
    return $null
}

1..254 | ForEach-Object {
    $ip = "$Subnet$_"
    $ps = [PowerShell]::Create().AddScript($scriptBlock).AddArgument($ip).AddArgument($Timeout)
    $ps.RunspacePool = $runspacePool
    $jobs += [pscustomobject]@{ Pipe = $ps; Result = $ps.BeginInvoke() }
}

$results = @()
foreach ($job in $jobs) {
    $output = $job.Pipe.EndInvoke($job.Result)
    if ($output) { $results += $output }
    $job.Pipe.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()

if ($results) {
    Write-Host "`nЗнайдено хостів: $($results.Count)" -ForegroundColor Green
    $results | Sort-Object { [version]$_.IP } | Format-Table -AutoSize
} else {
    Write-Host "Жодного хоста не відповіло." -ForegroundColor Yellow
}
