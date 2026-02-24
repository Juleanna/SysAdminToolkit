$script:ToolkitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path $PSCommandPath -Parent))
$script:ConfigPath = Join-Path $script:ToolkitRoot "Config\ToolkitConfig.json"

# ============================================================
#  Шляхи та конфігурація
# ============================================================

function Get-ToolkitRoot {
    <#
        .SYNOPSIS
        Повертає кореневу папку SysAdminToolkit.
    #>
    return $script:ToolkitRoot
}

function Get-ToolkitConfig {
    <#
        .SYNOPSIS
        Завантажує ToolkitConfig.json з дефолтними значеннями.
    #>
    $defaults = [pscustomobject]@{
        CompanyName              = "Dafna"
        DefaultBackupPath        = "D:\Backups"
        Subnet                   = "192.168.1."
        Description              = "SysAdminToolkit v5.0"
        LogLevel                 = "INFO"
        MaxLogSizeMB             = 10
        BackupRetentionDays      = 30
        RemoteTimeoutSec         = 30
        RetryCount               = 3
        DiskSpaceWarningPercent  = 80
        DiskSpaceCriticalPercent = 95
        CertExpiryWarnDays       = 30
        CriticalServices         = @("Spooler","wuauserv","WinDefend","EventLog","Dnscache")
        EmailSmtp                = ""
        EmailTo                  = ""
        EmailFrom                = ""
    }

    if (-not (Test-Path $script:ConfigPath)) {
        return $defaults
    }

    try {
        $cfg = Get-Content -Path $script:ConfigPath -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $defaults
    }

    foreach ($name in $defaults.PSObject.Properties.Name) {
        if ($null -eq $cfg.$name -or ($cfg.$name -is [string] -and [string]::IsNullOrWhiteSpace($cfg.$name))) {
            $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $defaults.$name -Force
        }
    }

    return $cfg
}

function Get-TkHostsList {
    <#
        .SYNOPSIS
        Завантажує список хостів з Config/Hosts.json.
    #>
    $hostsPath = Join-Path $script:ToolkitRoot "Config\Hosts.json"
    if (-not (Test-Path $hostsPath)) { return @() }
    try {
        $data = Get-Content $hostsPath -Encoding UTF8 | ConvertFrom-Json
        return $data.Hosts
    } catch {
        Write-Warning "Не вдалося завантажити Hosts.json: $_"
        return @()
    }
}

# ============================================================
#  Параметри
# ============================================================

function ConvertFrom-ParamString {
    <#
        .SYNOPSIS
        Перетворює рядок "Param1=Value1;Param2=Value2" у Hashtable для сплаттингу параметрів.
    #>
    param([string]$ParamString)

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($ParamString)) {
        return $map
    }

    $parts = $ParamString -split ';' | Where-Object { $_.Trim() }
    foreach ($part in $parts) {
        if ($part -notmatch '=') { continue }
        $kv = $part.Split('=', 2)
        $key = $kv[0].Trim()
        $val = $kv[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $val
        }
    }
    return $map
}

# ============================================================
#  Перевірки та валідація
# ============================================================

function Assert-Administrator {
    <#
        .SYNOPSIS
        Перевіряє наявність прав адміністратора. Завершує скрипт якщо прав немає.
    #>
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Потрібні права адміністратора."
        exit 1
    }
}

function Test-ComputerOnline {
    <#
        .SYNOPSIS
        Перевіряє доступність комп'ютера по мережі.
        .PARAMETER ComputerName
        Ім'я або IP комп'ютера.
        .PARAMETER TimeoutMs
        Таймаут пінгу в мілісекундах.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [int]$TimeoutMs = 2000
    )
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($ComputerName, $TimeoutMs)
        $ping.Dispose()
        return $reply.Status -eq 'Success'
    } catch {
        return $false
    }
}

# ============================================================
#  Логування
# ============================================================

function Write-TkLog {
    <#
        .SYNOPSIS
        Записує повідомлення в лог-файл тулкіту з рівнем та ротацією.
        .PARAMETER Message
        Текст повідомлення.
        .PARAMETER Level
        Рівень: DEBUG, INFO, WARN, ERROR.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $cfg = Get-ToolkitConfig
    $levelOrder = @{ 'DEBUG'=0; 'INFO'=1; 'WARN'=2; 'ERROR'=3 }
    $cfgLevel = if ($cfg.LogLevel -and $levelOrder.ContainsKey($cfg.LogLevel)) { $cfg.LogLevel } else { 'INFO' }
    if ($levelOrder[$Level] -lt $levelOrder[$cfgLevel]) { return }

    $logDir = Join-Path $script:ToolkitRoot "Logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir "Toolkit.log"

    # Ротація
    if ((Test-Path $logFile)) {
        $sizeMB = (Get-Item $logFile).Length / 1MB
        $maxMB = if ($cfg.MaxLogSizeMB) { $cfg.MaxLogSizeMB } else { 10 }
        if ($sizeMB -ge $maxMB) {
            $archiveName = Join-Path $logDir ("Toolkit_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            Move-Item $logFile $archiveName -Force -ErrorAction SilentlyContinue
        }
    }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts`t[$Level]`t$Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# ============================================================
#  Retry / Timeout
# ============================================================

function Invoke-WithRetry {
    <#
        .SYNOPSIS
        Виконує ScriptBlock з повторними спробами при помилці.
        .PARAMETER ScriptBlock
        Код для виконання.
        .PARAMETER MaxRetries
        Максимум повторних спроб.
        .PARAMETER DelaySeconds
        Затримка між спробами.
    #>
    param(
        [Parameter(Mandatory=$true)][ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return (& $ScriptBlock)
        } catch {
            if ($attempt -gt $MaxRetries) { throw }
            Write-TkLog "Спроба $attempt/$MaxRetries не вдалася: $($_.Exception.Message). Повтор через ${DelaySeconds}с..." -Level WARN
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# ============================================================
#  Звіти (HTML / Export)
# ============================================================

function Export-TkReport {
    <#
        .SYNOPSIS
        Експортує дані у файл (CSV, JSON або HTML).
        .PARAMETER Data
        Масив об'єктів для експорту.
        .PARAMETER Path
        Шлях до файлу.
        .PARAMETER Title
        Заголовок HTML-звіту.
        .PARAMETER Format
        Формат: CSV, JSON, HTML.
    #>
    param(
        [Parameter(Mandatory=$true)]$Data,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Title = "SysAdminToolkit Report",
        [ValidateSet('CSV','JSON','HTML')]
        [string]$Format = 'HTML'
    )

    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    switch ($Format) {
        'CSV'  { $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
        'JSON' { $Data | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8 }
        'HTML' {
            $cfg = Get-ToolkitConfig
            $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $rows = $Data | ConvertTo-Html -Fragment
            $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>$Title</title>
<style>
  body { font-family: Segoe UI, sans-serif; margin: 20px; background: #1e1e2e; color: #cdd6f4; }
  h1 { color: #89b4fa; } h2 { color: #a6adc8; }
  table { border-collapse: collapse; width: 100%; margin-top: 10px; }
  th { background: #313244; color: #cba6f7; padding: 8px 12px; text-align: left; border-bottom: 2px solid #45475a; }
  td { padding: 6px 12px; border-bottom: 1px solid #313244; }
  tr:hover { background: #313244; }
  .meta { color: #6c7086; font-size: 0.85em; margin-bottom: 15px; }
</style></head><body>
<h1>$Title</h1>
<div class="meta">$($cfg.CompanyName) | $($env:COMPUTERNAME) | $date</div>
$rows
</body></html>
"@
            Set-Content -Path $Path -Value $html -Encoding UTF8
        }
    }
    Write-TkLog "Звіт збережено: $Path ($Format)" -Level INFO
    return $Path
}

function ConvertTo-TkResult {
    <#
        .SYNOPSIS
        Створює стандартний об'єкт результату для уніфікованого виводу.
    #>
    param(
        [bool]$Success = $true,
        [string]$Message = "",
        $Data = $null
    )
    return [pscustomobject]@{
        Success   = $Success
        Message   = $Message
        Data      = $Data
        Timestamp = Get-Date
        Computer  = $env:COMPUTERNAME
    }
}

# ============================================================
#  Email
# ============================================================

function Send-TkEmail {
    <#
        .SYNOPSIS
        Надсилає email-повідомлення через SMTP (конфіг з ToolkitConfig.json).
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body,
        [string]$To,
        [string[]]$Attachments
    )
    $cfg = Get-ToolkitConfig
    if ([string]::IsNullOrWhiteSpace($cfg.EmailSmtp)) {
        Write-Warning "SMTP не налаштовано в конфігу (EmailSmtp)."
        return
    }
    $emailTo = if ($To) { $To } else { $cfg.EmailTo }
    if ([string]::IsNullOrWhiteSpace($emailTo)) {
        Write-Warning "Адреса отримувача не вказана (EmailTo)."
        return
    }
    $params = @{
        From       = if ($cfg.EmailFrom) { $cfg.EmailFrom } else { "toolkit@$($env:COMPUTERNAME)" }
        To         = $emailTo
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $cfg.EmailSmtp
        BodyAsHtml = $true
    }
    if ($Attachments) { $params.Attachments = $Attachments }
    try {
        Send-MailMessage @params -ErrorAction Stop
        Write-TkLog "Email надіслано: $Subject -> $emailTo" -Level INFO
    } catch {
        Write-TkLog "Не вдалося надіслати email: $($_.Exception.Message)" -Level ERROR
        Write-Warning "Не вдалося надіслати email: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-ToolkitRoot, Get-ToolkitConfig, Get-TkHostsList, `
    ConvertFrom-ParamString, Assert-Administrator, Test-ComputerOnline, `
    Write-TkLog, Invoke-WithRetry, Export-TkReport, ConvertTo-TkResult, Send-TkEmail
