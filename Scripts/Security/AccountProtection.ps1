param(
    [ValidateSet('Status','EnableSecure','Relax')]
    [string]$Mode = 'Status'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($Mode -ne 'Status' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора."
    exit 1
}

$lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$smartPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

function Show-State {
    $lsa = Get-ItemProperty -Path $lsaPath -ErrorAction SilentlyContinue
    $smart = Get-ItemProperty -Path $smartPath -ErrorAction SilentlyContinue
    $wl = Get-ItemProperty -Path $winlogon -ErrorAction SilentlyContinue
    [pscustomobject]@{
        RunAsPPL          = $lsa.RunAsPPL
        LsaCfgFlags       = $lsa.LsaCfgFlags
        CachedLogonsCount = $wl.CachedLogonsCount
        SmartScreen       = $smart.SmartScreenEnabled
        SmartScreenLevel  = $smart.ShellSmartScreenLevel
    } | Format-List
}

if ($Mode -eq 'Status') {
    Write-Host "Статус LSA/SmartScreen/кеш логінів:" -ForegroundColor Cyan
    Show-State
    exit 0
}

if ($Mode -eq 'EnableSecure') {
    try { New-Item -Path $lsaPath -Force | Out-Null } catch {}
    try { Set-ItemProperty -Path $lsaPath -Name 'RunAsPPL' -Value 1 -Type DWord -ErrorAction Stop } catch { Write-Warning "RunAsPPL: $_" }
    try { Set-ItemProperty -Path $lsaPath -Name 'LsaCfgFlags' -Value 1 -Type DWord -ErrorAction Stop } catch { Write-Warning "LsaCfgFlags: $_" }
    try { Set-ItemProperty -Path $winlogon -Name 'CachedLogonsCount' -Value '0' -Type String -ErrorAction Stop } catch { Write-Warning "CachedLogonsCount: $_" }
    try { New-Item -Path $smartPath -Force | Out-Null } catch {}
    try { Set-ItemProperty -Path $smartPath -Name 'SmartScreenEnabled' -Value 1 -Type DWord -ErrorAction Stop } catch { Write-Warning "SmartScreen: $_" }
    try { Set-ItemProperty -Path $smartPath -Name 'ShellSmartScreenLevel' -Value 'Block' -Type String -ErrorAction Stop } catch { Write-Warning "SmartScreenLevel: $_" }
}

if ($Mode -eq 'Relax') {
    try { Set-ItemProperty -Path $lsaPath -Name 'RunAsPPL' -Value 0 -Type DWord -ErrorAction Stop } catch { Write-Warning "RunAsPPL: $_" }
    try { Set-ItemProperty -Path $lsaPath -Name 'LsaCfgFlags' -Value 0 -Type DWord -ErrorAction Stop } catch { Write-Warning "LsaCfgFlags: $_" }
    try { Set-ItemProperty -Path $winlogon -Name 'CachedLogonsCount' -Value '10' -Type String -ErrorAction Stop } catch { Write-Warning "CachedLogonsCount: $_" }
    try { Set-ItemProperty -Path $smartPath -Name 'SmartScreenEnabled' -Value 0 -Type DWord -ErrorAction Stop } catch { Write-Warning "SmartScreen: $_" }
    try { Set-ItemProperty -Path $smartPath -Name 'ShellSmartScreenLevel' -Value 'Warn' -Type String -ErrorAction Stop } catch { Write-Warning "SmartScreenLevel: $_" }
}

Write-Host "Завершено ($Mode). Поточний стан:" -ForegroundColor Cyan
Show-State
