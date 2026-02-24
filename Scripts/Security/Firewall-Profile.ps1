param(
    [ValidateSet('Status','Enable','Disable','Toggle')]
    [string]$Mode = 'Toggle',
    [ValidateSet('Domain','Private','Public','All')]
    [string]$Profile = 'All'
)

$needsAdmin = $Mode -ne 'Status'
if ($needsAdmin) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Потрібні права адміністратора для зміни брандмауера."
        exit 1
    }
}

$profiles = if ($Profile -eq 'All') { @('Domain','Private','Public') } else { @($Profile) }

function Show-Status($pf) {
    try {
        Get-NetFirewallProfile -Profile $pf -ErrorAction Stop |
            Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction |
            Format-Table -AutoSize
    } catch {
        Write-Error "Не вдалося отримати статус брандмауера: $($_.Exception.Message)"
    }
}

try {
    $current = Get-NetFirewallProfile -Profile $profiles -ErrorAction Stop
} catch {
    Write-Error "Не вдалося отримати поточний статус брандмауера: $($_.Exception.Message)"
    exit 1
}

if ($Mode -eq 'Status') {
    Write-Host "Поточний статус брандмауера:" -ForegroundColor Cyan
    Show-Status $profiles
    exit 0
}

$anyEnabled = ($current.Enabled -contains $true)
$targetEnabled = switch ($Mode) {
    'Enable' { $true }
    'Disable' { $false }
    'Toggle' { -not $anyEnabled }
}

# Для увімкнення потрібно запустити сервіси BFE та MpsSvc
if ($targetEnabled) {
    foreach ($svcName in 'bfe','mpssvc') {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne 'Running') { Start-Service -Name $svcName -ErrorAction Stop }
        } catch {
            Write-Warning "Не вдалося запустити сервіс ${svcName}: $($_.Exception.Message)"
        }
    }
}

$gpoBool = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]
$enableValue = if ($targetEnabled) { $gpoBool::True } else { $gpoBool::False }
$setOk = $false

try {
    foreach ($p in $profiles) {
        Set-NetFirewallProfile -Profile $p -Enabled $enableValue -ErrorAction Stop
    }
    $setOk = $true
} catch {
    Write-Warning "Set-NetFirewallProfile не спрацювала: $($_.Exception.Message). Спроба через netsh."
}

if (-not $setOk) {
    foreach ($p in $profiles) {
        $pName = $p.ToLower()
        $state = if ($targetEnabled) { 'on' } else { 'off' }
        try {
            netsh advfirewall set $pName state $state | Out-Null
            $setOk = $true
        } catch {
            Write-Warning "Не вдалося виконати netsh для профілю ${p}: $($_.Exception.Message)"
        }
    }
}

if (-not $setOk) {
    Write-Error "Не вдалося змінити параметри брандмауера."
    exit 1
}

Write-Host "Брандмауер змінено (Mode=$Mode, target=$targetEnabled)." -ForegroundColor Cyan
Show-Status $profiles
