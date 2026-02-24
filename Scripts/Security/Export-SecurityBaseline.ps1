<#
.SYNOPSIS
    Експортує поточні налаштування безпеки системи як JSON-базелайн.

.DESCRIPTION
    Збирає комплексну інформацію про безпеку системи: профілі брандмауера, статус RDP,
    статус USB-накопичувачів, аудит-політики, локальні адміністратори, парольна політика,
    конфігурація SMB та рівень NTLM. Зберігає все у форматі JSON для подальшого
    порівняння або аудиту.

.PARAMETER OutputPath
    Шлях до файлу для збереження базелайну. За замовчуванням зберігається
    у кореневій папці тулкіту як SecurityBaseline_<ComputerName>_<дата>.json.

.EXAMPLE
    .\Export-SecurityBaseline.ps1
    Зберігає базелайн з автоматичною назвою у корені тулкіту.

.EXAMPLE
    .\Export-SecurityBaseline.ps1 -OutputPath "D:\Backups\baseline.json"
    Зберігає базелайн у вказаний файл.
#>

param(
    [string]$OutputPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Assert-Administrator

Write-TkLog "Запуск експорту базелайну безпеки" -Level INFO

$toolkitRoot = Get-ToolkitRoot

if (-not $OutputPath) {
    $date = Get-Date -Format "yyyy-MM-dd"
    $OutputPath = Join-Path $toolkitRoot "SecurityBaseline_${env:COMPUTERNAME}_${date}.json"
}

$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$baseline = [ordered]@{
    ComputerName = $env:COMPUTERNAME
    ExportDate   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    OSVersion    = [System.Environment]::OSVersion.VersionString
}

Write-Host "Збір базелайну безпеки для $env:COMPUTERNAME..." -ForegroundColor Cyan

# --- 1. Профілі брандмауера ---
Write-Host "  [1/8] Профілі брандмауера..." -ForegroundColor Gray
try {
    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            Name               = $_.Name
            Enabled            = $_.Enabled
            DefaultInboundAction  = $_.DefaultInboundAction.ToString()
            DefaultOutboundAction = $_.DefaultOutboundAction.ToString()
            LogAllowed         = $_.LogAllowed
            LogBlocked         = $_.LogBlocked
        }
    }
    $baseline.FirewallProfiles = $fwProfiles
} catch {
    $baseline.FirewallProfiles = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати профілі брандмауера: $($_.Exception.Message)"
}

# --- 2. Статус RDP ---
Write-Host "  [2/8] Статус RDP..." -ForegroundColor Gray
try {
    $tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $nlaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $fDeny = (Get-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections
    $nla = (Get-ItemProperty -Path $nlaPath -Name 'UserAuthentication' -ErrorAction Stop).UserAuthentication
    $baseline.RDP = [ordered]@{
        Enabled = [bool](1 - $fDeny)
        NLA     = [bool]$nla
    }
} catch {
    $baseline.RDP = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати статус RDP: $($_.Exception.Message)"
}

# --- 3. Статус USB ---
Write-Host "  [3/8] Статус USB-накопичувачів..." -ForegroundColor Gray
try {
    $usbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
    $usbStart = (Get-ItemProperty -Path $usbPath -Name 'Start' -ErrorAction Stop).Start
    $baseline.USBStorage = [ordered]@{
        StartValue = $usbStart
        Enabled    = ($usbStart -ne 4)
        Status     = if ($usbStart -eq 4) { "Заблоковано" } elseif ($usbStart -eq 3) { "Увімкнено" } else { "Значення: $usbStart" }
    }
} catch {
    $baseline.USBStorage = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати статус USB: $($_.Exception.Message)"
}

# --- 4. Аудит-політики ---
Write-Host "  [4/8] Аудит-політики..." -ForegroundColor Gray
try {
    $auditRaw = & auditpol /get /category:* 2>&1
    $auditPolicies = @()
    foreach ($line in $auditRaw) {
        if ($line -match '^\s{2}\S' -and $line -match '(Success|Failure|No Auditing|Успіх|Помилка)') {
            $parts = $line.Trim() -split '\s{2,}'
            if ($parts.Count -ge 2) {
                $auditPolicies += [ordered]@{
                    Subcategory = $parts[0].Trim()
                    Setting     = $parts[1].Trim()
                }
            }
        }
    }
    $baseline.AuditPolicies = $auditPolicies
} catch {
    $baseline.AuditPolicies = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати аудит-політики: $($_.Exception.Message)"
}

# --- 5. Локальні адміністратори ---
Write-Host "  [5/8] Локальні адміністратори..." -ForegroundColor Gray
try {
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            Name          = $_.Name
            ObjectClass   = $_.ObjectClass
            PrincipalSource = $_.PrincipalSource.ToString()
        }
    }
    $baseline.LocalAdmins = $admins
} catch {
    # Fallback через net localgroup
    try {
        $netOutput = & net localgroup Administrators 2>&1
        $members = $netOutput | Where-Object { $_ -and $_ -notmatch '^(Alias|Comment|Members|The command|---)' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $baseline.LocalAdmins = $members
    } catch {
        $baseline.LocalAdmins = "Помилка: $($_.Exception.Message)"
        Write-Warning "  Не вдалося отримати локальних адміністраторів: $($_.Exception.Message)"
    }
}

# --- 6. Парольна політика ---
Write-Host "  [6/8] Парольна політика..." -ForegroundColor Gray
try {
    $netAccounts = & cmd.exe /c 'net accounts' 2>&1
    $passwordPolicy = [ordered]@{}
    foreach ($line in $netAccounts) {
        if ($line -match ':') {
            $kv = $line -split '\s*:\s*', 2
            if ($kv.Count -eq 2 -and $kv[0].Trim()) {
                $passwordPolicy[$kv[0].Trim()] = $kv[1].Trim()
            }
        }
    }
    $baseline.PasswordPolicy = $passwordPolicy
} catch {
    $baseline.PasswordPolicy = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати парольну політику: $($_.Exception.Message)"
}

# --- 7. Конфігурація SMB ---
Write-Host "  [7/8] Конфігурація SMB..." -ForegroundColor Gray
try {
    $smbServer = Get-SmbServerConfiguration -ErrorAction Stop
    $baseline.SMBConfig = [ordered]@{
        EnableSMB1Protocol    = $smbServer.EnableSMB1Protocol
        EnableSMB2Protocol    = $smbServer.EnableSMB2Protocol
        RequireSecuritySignature = $smbServer.RequireSecuritySignature
        EnableSecuritySignature  = $smbServer.EnableSecuritySignature
        EncryptData           = $smbServer.EncryptData
        RejectUnencryptedAccess = $smbServer.RejectUnencryptedAccess
    }
} catch {
    $baseline.SMBConfig = "Помилка: $($_.Exception.Message)"
    Write-Warning "  Не вдалося отримати конфігурацію SMB: $($_.Exception.Message)"
}

# --- 8. Рівень NTLM ---
Write-Host "  [8/8] Рівень NTLM..." -ForegroundColor Gray
try {
    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $ntlmLevel = (Get-ItemProperty -Path $lsaPath -Name 'LmCompatibilityLevel' -ErrorAction Stop).LmCompatibilityLevel
    $ntlmDesc = switch ($ntlmLevel) {
        0 { "Send LM & NTLM responses" }
        1 { "Send LM & NTLM - use NTLMv2 session security if negotiated" }
        2 { "Send NTLM response only" }
        3 { "Send NTLMv2 response only" }
        4 { "Send NTLMv2 response only. Refuse LM" }
        5 { "Send NTLMv2 response only. Refuse LM & NTLM" }
        default { "Невідоме значення: $ntlmLevel" }
    }
    $baseline.NTLMLevel = [ordered]@{
        LmCompatibilityLevel = $ntlmLevel
        Description          = $ntlmDesc
    }
} catch {
    $baseline.NTLMLevel = [ordered]@{
        LmCompatibilityLevel = "Не задано (за замовчуванням)"
        Description          = "Значення не встановлено в реєстрі"
    }
}

# --- Збереження ---
try {
    $baseline | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -ErrorAction Stop
    Write-Host "`nБазелайн безпеки успішно збережено:" -ForegroundColor Green
    Write-Host "  $OutputPath" -ForegroundColor Yellow
    Write-TkLog "Базелайн безпеки збережено: $OutputPath" -Level INFO
} catch {
    Write-Error "Не вдалося зберегти базелайн: $($_.Exception.Message)"
    Write-TkLog "Помилка збереження базелайну: $($_.Exception.Message)" -Level ERROR
    exit 1
}
