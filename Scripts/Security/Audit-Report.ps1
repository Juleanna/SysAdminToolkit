param(
    [int]$Hours = 24
)

$start = (Get-Date).AddHours(-[math]::Abs($Hours))
# 4624=Logon, 4625=Failed logon, 4672=Special privileges, 4720=User created, 4726=User deleted
$ids = 4624,4625,4672,4720,4726

try {
    $events = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=$ids; StartTime=$start } -ErrorAction Stop | Select-Object -First 200
} catch {
    Write-Error "Не вдалося отримати події Security: $($_.Exception.Message)"
    exit 1
}

if (-not $events) {
    Write-Host "Подій не знайдено за останні $Hours годин." -ForegroundColor Yellow
    exit 0
}

Write-Host "Останні події безпеки (макс. 200), годин: $Hours" -ForegroundColor Cyan
$events | ForEach-Object {
    $msg = $_.Message -replace "\s+"," "
    if ($msg.Length -gt 200) { $msg = $msg.Substring(0,200) + '...' }
    [pscustomobject]@{
        Time = $_.TimeCreated
        Id   = $_.Id
        User = if ($_.Properties.Count -gt 1) { $_.Properties[1].Value } else { '-' }
        Desc = $msg
    }
} | Format-Table -AutoSize
