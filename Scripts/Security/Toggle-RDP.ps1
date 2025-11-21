param(
    [ValidateSet('Enable','Disable','Toggle','Status')]
    [string]$Mode = 'Toggle'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$requiresAdmin = $Mode -ne 'Status'
if ($requiresAdmin -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Требуются права администратора для управления RDP."
    exit 1
}

$tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$nlaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

try {
    $currentDeny = (Get-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections
    $currentNla  = (Get-ItemProperty -Path $nlaPath -Name 'UserAuthentication' -ErrorAction Stop).UserAuthentication
} catch {
    Write-Error "Не удалось прочитать состояние RDP: $($_.Exception.Message)"
    exit 1
}

if ($Mode -eq 'Status') {
    Write-Host "RDP включён: $([bool](1 - $currentDeny))" -ForegroundColor Cyan
    Write-Host "NLA: $([bool]$currentNla)" -ForegroundColor Cyan
    exit 0
}

$targetDeny = switch ($Mode) {
    'Enable' { 0 }
    'Disable' { 1 }
    'Toggle' { if ($currentDeny -eq 1) { 0 } else { 1 } }
    default { $currentDeny }
}

$targetNla = if ($targetDeny -eq 0) { 1 } else { 0 }

try {
    Set-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -Value $targetDeny -ErrorAction Stop
    Set-ItemProperty -Path $nlaPath -Name 'UserAuthentication' -Value $targetNla -ErrorAction Stop
} catch {
    Write-Error "Не удалось изменить состояние RDP: $($_.Exception.Message)"
    exit 1
}

if ($targetDeny -eq 0) {
    try {
        Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop | Set-NetFirewallRule -Enabled True
    } catch {
        Write-Warning "Не удалось включить правила брандмауэра для RDP: $($_.Exception.Message)"
    }
} else {
    try {
        Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop | Set-NetFirewallRule -Enabled False
    } catch {
        Write-Warning "Не удалось отключить правила брандмауэра для RDP: $($_.Exception.Message)"
    }
}

$finalState = if ($targetDeny -eq 0) { 'включён' } else { 'выключен' }
$finalNla   = if ($targetNla -eq 1) { 'включена' } else { 'выключена' }
Write-Host "RDP $finalState. NLA $finalNla." -ForegroundColor Green
