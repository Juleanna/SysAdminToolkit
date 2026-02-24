param(
    [ValidateSet('Status','Lockdown','EnableWinRM')]
    [string]$Mode = 'Status'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($Mode -ne 'Status' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора."
    exit 1
}

function Set-ServiceMode($name,$start,$state) {
    try {
        Set-Service -Name $name -StartupType $start -ErrorAction Stop
        if ($state -eq 'Stopped') { Stop-Service -Name $name -Force -ErrorAction Stop }
        if ($state -eq 'Running') { Start-Service -Name $name -ErrorAction Stop }
    } catch {
        Write-Warning "Не вдалося змінити сервіс ${name}: $($_.Exception.Message)"
    }
}

$descTable = @{
    WinRM_Status  = 'WinRM (PSRemoting): Running = ввімкнено, Stopped = вимкнено.'
    SMB1_Disabled = 'SMB1: True = вимкнено (безпечно), False = увімкнено (небезпечно).'
    NTLM_Level    = 'LmCompatibilityLevel (NTLM): 5 = тільки NTLMv2 (безпечно); 0-2 = знижено, потрібно підвищити.'
}

function Show-State {
    $winrmSvc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $smb      = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    $lm       = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -ErrorAction SilentlyContinue

    $winrmStatus = if ($winrmSvc) { $winrmSvc.Status } else { $null }
    $smbDisabled = if ($smb) { -not $smb.EnableSMB1Protocol } else { $null }
    $ntlmLevel   = if ($lm)  { $lm.LmCompatibilityLevel } else { $null }

    $obj = [pscustomobject]@{
        WinRM_Status  = $winrmStatus
        SMB1_Disabled = $smbDisabled
        NTLM_Level    = $ntlmLevel
    }

    $obj | Format-List
    Write-Host ""
    foreach ($p in $obj.PSObject.Properties) {
        if ($descTable.ContainsKey($p.Name)) {
            Write-Host ("{0}: {1}" -f $p.Name,$descTable[$p.Name]) -ForegroundColor Gray
        }
    }
}

if ($Mode -eq 'Status') {
    Write-Host "Поточний статус WinRM/SMB1/NTLM:" -ForegroundColor Cyan
    Show-State
    exit 0
}

# Lockdown: вимкнути WinRM, вимкнути SMB1, встановити NTLM level=5
if ($Mode -eq 'Lockdown') {
    Set-ServiceMode -name 'WinRM' -start Disabled -state 'Stopped'
    try { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop } catch { Write-Warning "SMB1: $_" }
    try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 5 -Type DWord -ErrorAction Stop } catch { Write-Warning "NTLM рівень: $_" }
}

# EnableWinRM: увімкнути WinRM та PSRemoting, SMB1 завжди вимикається
if ($Mode -eq 'EnableWinRM') {
    Set-ServiceMode -name 'WinRM' -start Automatic -state 'Running'
    try { Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop } catch { Write-Warning "PSRemoting: $_" }
    try { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop } catch { Write-Warning "SMB1: $_" }
}

Write-Host "Завершено ($Mode). Поточні налаштування:" -ForegroundColor Cyan
Show-State
