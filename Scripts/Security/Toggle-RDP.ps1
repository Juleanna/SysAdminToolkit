param(
    [ValidateSet('Enable','Disable','Toggle','Status')]
    [string]$Mode = 'Toggle'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$requiresAdmin = $Mode -ne 'Status'
if ($requiresAdmin -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора для керування RDP."
    exit 1
}

$tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$nlaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

try {
    $currentDeny = (Get-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections
    $currentNla  = (Get-ItemProperty -Path $nlaPath -Name 'UserAuthentication' -ErrorAction Stop).UserAuthentication
} catch {
    Write-Error "Не вдалося прочитати параметри RDP: $($_.Exception.Message)"
    exit 1
}

if ($Mode -eq 'Status') {
    Write-Host "RDP увімкнено: $([bool](1 - $currentDeny))" -ForegroundColor Cyan
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
    Write-Error "Не вдалося змінити параметри RDP: $($_.Exception.Message)"
    exit 1
}

# Оновлення правил брандмауера для порту 3389
$rdpRules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*Remote Desktop*' -or $_.Name -like '*rdp*' -or $_.DisplayGroup -like '*Remote Desktop*' }
if ($rdpRules) {
    try {
        $state = if ($targetDeny -eq 0) { 'True' } else { 'False' }
        $rdpRules | Set-NetFirewallRule -Enabled $state -ErrorAction Stop
    } catch {
        Write-Warning "Не вдалося оновити правила брандмауера для RDP: $($_.Exception.Message)"
    }
}

$finalState = if ($targetDeny -eq 0) { 'Увімкнено' } else { 'Вимкнено' }
$finalNla   = if ($targetNla -eq 1) { 'Увімкнено' } else { 'Вимкнено' }
Write-Host "RDP $finalState. NLA $finalNla." -ForegroundColor Green
