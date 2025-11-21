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
        Write-Error "Требуются права администратора для изменения брандмауэра."
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
        Write-Error "Не удалось получить статус брандмауэра: $($_.Exception.Message)"
    }
}

try {
    $current = Get-NetFirewallProfile -Profile $profiles -ErrorAction Stop
} catch {
    Write-Error "Не удалось получить текущий статус брандмауэра: $($_.Exception.Message)"
    exit 1
}

if ($Mode -eq 'Status') {
    Write-Host "Текущий статус брандмауэра:" -ForegroundColor Cyan
    Show-Status $profiles
    exit 0
}

$anyEnabled = ($current.Enabled -contains $true)
$targetEnabled = switch ($Mode) {
    'Enable' { $true }
    'Disable' { $false }
    'Toggle' { -not $anyEnabled }
}

# При включении пробуем поднять службы BFE и MpsSvc, иначе Set-NetFirewallProfile не сработает.
if ($targetEnabled) {
    foreach ($svcName in 'bfe','mpssvc') {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne 'Running') { Start-Service -Name $svcName -ErrorAction Stop }
        } catch {
            Write-Warning "Не удалось запустить службу ${svcName}: $($_.Exception.Message)"
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
    Write-Warning "Set-NetFirewallProfile не сработал: $($_.Exception.Message). Попробую netsh advfirewall." 
}

if (-not $setOk) {
    foreach ($p in $profiles) {
        $pName = $p.ToLower()
        $state = if ($targetEnabled) { 'on' } else { 'off' }
        try {
            # netsh не поддерживает All разом
            netsh advfirewall set $pName state $state | Out-Null
            $setOk = $true
        } catch {
            Write-Warning "Не удалось через netsh для профиля ${p}: $($_.Exception.Message)"
        }
    }
}

if (-not $setOk) {
    Write-Error "Не удалось изменить состояние брандмауэра."
    exit 1
}

Write-Host "Брандмауэр обновлён (Mode=$Mode, target=$targetEnabled)." -ForegroundColor Cyan
Show-Status $profiles
