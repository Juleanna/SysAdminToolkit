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

# ============================================================
#  Сповіщення
# ============================================================

function Show-TkNotification {
    <#
        .SYNOPSIS
        Показує WPF toast-сповіщення (balloon) в системному треї.
        .PARAMETER Title
        Заголовок сповіщення.
        .PARAMETER Message
        Текст сповіщення.
        .PARAMETER Icon
        Тип іконки: Info, Warning, Error.
        .PARAMETER DurationMs
        Тривалість показу в мілісекундах.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Icon = 'Info',
        [int]$DurationMs = 5000
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        if ($Icon -eq 'Warning') { $notify.Icon = [System.Drawing.SystemIcons]::Warning }
        elseif ($Icon -eq 'Error') { $notify.Icon = [System.Drawing.SystemIcons]::Error }
        $notify.Visible = $true
        $tipIcon = [System.Windows.Forms.ToolTipIcon]::$Icon
        $notify.ShowBalloonTip($DurationMs, $Title, $Message, $tipIcon)
        Start-Sleep -Milliseconds ($DurationMs + 500)
        $notify.Dispose()
    } catch {
        Write-TkLog "Не вдалося показати сповіщення: $($_.Exception.Message)" -Level WARN
    }
}

# ============================================================
#  Віддалене виконання
# ============================================================

function Invoke-TkRemote {
    <#
        .SYNOPSIS
        Обгортка для Invoke-Command з автоматичним retry, логуванням та таймаутом.
        .PARAMETER ComputerName
        Ім'я або IP комп'ютера.
        .PARAMETER ScriptBlock
        Блок коду для виконання.
        .PARAMETER ArgumentList
        Аргументи для ScriptBlock.
        .PARAMETER Credential
        Облікові дані (PSCredential).
    #>
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][ScriptBlock]$ScriptBlock,
        [object[]]$ArgumentList,
        [PSCredential]$Credential
    )
    $cfg = Get-ToolkitConfig

    if (-not (Test-ComputerOnline -ComputerName $ComputerName -TimeoutMs ($cfg.RemoteTimeoutSec * 1000))) {
        Write-TkLog "Invoke-TkRemote: $ComputerName недоступний" -Level ERROR
        Write-Error "Комп'ютер $ComputerName недоступний."
        return $null
    }

    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }
    if ($ArgumentList) { $invokeParams.ArgumentList = $ArgumentList }
    if ($Credential)   { $invokeParams.Credential   = $Credential }

    $retryCount = if ($cfg.RetryCount) { $cfg.RetryCount } else { 3 }

    try {
        $result = Invoke-WithRetry -ScriptBlock {
            Invoke-Command @invokeParams
        } -MaxRetries $retryCount -DelaySeconds 2
        Write-TkLog "Invoke-TkRemote: $ComputerName — успішно" -Level INFO
        return $result
    } catch {
        Write-TkLog "Invoke-TkRemote: $ComputerName — помилка: $($_.Exception.Message)" -Level ERROR
        Write-Error "Помилка виконання на $ComputerName : $($_.Exception.Message)"
        return $null
    }
}

# ============================================================
#  Облікові дані (DPAPI)
# ============================================================

function Get-TkCredential {
    <#
        .SYNOPSIS
        Отримує або створює збережені облікові дані через DPAPI.
        .PARAMETER Name
        Унікальне ім'я для облікових даних (наприклад, "DomainAdmin").
        .PARAMETER Force
        Примусово запитати нові дані навіть якщо збережені існують.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [switch]$Force
    )
    $credDir = Join-Path $script:ToolkitRoot "Config\.credentials"
    if (-not (Test-Path $credDir)) { New-Item -ItemType Directory -Path $credDir -Force | Out-Null }
    $credFile = Join-Path $credDir "$Name.cred.xml"

    if ((Test-Path $credFile) -and -not $Force) {
        try {
            $cred = Import-Clixml -Path $credFile
            Write-TkLog "Облікові дані '$Name' завантажено з кешу" -Level DEBUG
            return $cred
        } catch {
            Write-TkLog "Не вдалося прочитати збережені дані '$Name': $($_.Exception.Message)" -Level WARN
        }
    }

    $cred = Get-Credential -Message "Введіть облікові дані для '$Name'"
    if ($null -eq $cred) { return $null }

    try {
        $cred | Export-Clixml -Path $credFile -Force
        Write-TkLog "Облікові дані '$Name' збережено (DPAPI)" -Level INFO
    } catch {
        Write-TkLog "Не вдалося зберегти дані '$Name': $($_.Exception.Message)" -Level WARN
    }
    return $cred
}

# ============================================================
#  Перевірка передумов
# ============================================================

function Test-TkPrerequisite {
    <#
        .SYNOPSIS
        Перевіряє передумови для виконання скрипту.
        .PARAMETER RequireAdmin
        Вимагати права адміністратора.
        .PARAMETER RequireModules
        Масив назв необхідних модулів.
        .PARAMETER RequirePS
        Мінімальна версія PowerShell.
        .PARAMETER RequireOnline
        Ім'я комп'ютера для перевірки доступності.
    #>
    param(
        [switch]$RequireAdmin,
        [string[]]$RequireModules,
        [version]$RequirePS,
        [string]$RequireOnline
    )
    $ok = $true

    if ($RequireAdmin) {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "ПОМИЛКА: Потрібні права адміністратора." -ForegroundColor Red
            $ok = $false
        }
    }

    if ($RequirePS) {
        if ($PSVersionTable.PSVersion -lt $RequirePS) {
            Write-Host "ПОМИЛКА: Потрібен PowerShell $RequirePS або новіший. Поточна версія: $($PSVersionTable.PSVersion)" -ForegroundColor Red
            $ok = $false
        }
    }

    foreach ($mod in $RequireModules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Host "ПОМИЛКА: Модуль '$mod' не знайдено. Встановіть його перед використанням." -ForegroundColor Red
            if ($mod -eq 'ActiveDirectory') {
                Write-Host "  Встановлення: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
            } elseif ($mod -eq 'GroupPolicy') {
                Write-Host "  Встановлення: Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -ForegroundColor Yellow
            }
            $ok = $false
        }
    }

    if ($RequireOnline) {
        if (-not (Test-ComputerOnline -ComputerName $RequireOnline)) {
            Write-Host "ПОМИЛКА: Комп'ютер '$RequireOnline' недоступний." -ForegroundColor Red
            $ok = $false
        }
    }

    return $ok
}

# ============================================================
#  HTML-дашборд
# ============================================================

function ConvertTo-TkHtmlDashboard {
    <#
        .SYNOPSIS
        Генерує зведений HTML-дашборд з кількох секцій даних.
        .PARAMETER Sections
        Масив хештаблиць: @{ Title="..."; Data=@(...) }
        .PARAMETER OutputPath
        Шлях до вихідного HTML-файлу.
        .PARAMETER DashboardTitle
        Заголовок дашборду.
    #>
    param(
        [Parameter(Mandatory=$true)][array]$Sections,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [string]$DashboardTitle = "SysAdminToolkit Dashboard"
    )

    $cfg = Get-ToolkitConfig
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $sectionsHtml = ""
    foreach ($section in $Sections) {
        $title = $section.Title
        $data = $section.Data
        if ($null -eq $data -or @($data).Count -eq 0) {
            $tableHtml = "<p class='empty'>Немає даних</p>"
        } else {
            $tableHtml = ($data | ConvertTo-Html -Fragment) -join "`n"
        }
        $statusClass = if ($section.Status) { " status-$($section.Status)" } else { "" }
        $sectionsHtml += @"
<div class="card$statusClass">
  <h2>$title</h2>
  $tableHtml
</div>
"@
    }

    $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>$DashboardTitle</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #1e1e2e; color: #cdd6f4; padding: 20px; }
  h1 { color: #89b4fa; margin-bottom: 5px; font-size: 1.6em; }
  .meta { color: #6c7086; font-size: 0.85em; margin-bottom: 20px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(480px, 1fr)); gap: 16px; }
  .card { background: #313244; border-radius: 8px; padding: 16px; border: 1px solid #45475a; }
  .card h2 { color: #cba6f7; font-size: 1.1em; margin-bottom: 10px; border-bottom: 1px solid #45475a; padding-bottom: 6px; }
  .card.status-ok { border-left: 4px solid #a6e3a1; }
  .card.status-warn { border-left: 4px solid #fab387; }
  .card.status-error { border-left: 4px solid #f38ba8; }
  table { border-collapse: collapse; width: 100%; font-size: 0.9em; }
  th { background: #45475a; color: #cba6f7; padding: 6px 10px; text-align: left; }
  td { padding: 5px 10px; border-bottom: 1px solid #3b3d52; }
  tr:hover { background: #3b3d52; }
  .empty { color: #6c7086; font-style: italic; }
  .footer { margin-top: 20px; color: #6c7086; font-size: 0.8em; text-align: center; }
</style></head><body>
<h1>$DashboardTitle</h1>
<div class="meta">$($cfg.CompanyName) | $($env:COMPUTERNAME) | $date</div>
<div class="grid">
$sectionsHtml
</div>
<div class="footer">SysAdminToolkit v5.0 | Згенеровано автоматично</div>
</body></html>
"@

    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    Write-TkLog "Дашборд збережено: $OutputPath" -Level INFO
    return $OutputPath
}

# ============================================================
#  Аудит-лог у Windows Event Log
# ============================================================

function Write-TkEventLog {
    <#
        .SYNOPSIS
        Записує подію до Windows Event Log (джерело SysAdminToolkit).
        .PARAMETER Message
        Текст повідомлення.
        .PARAMETER EntryType
        Тип: Information, Warning, Error.
        .PARAMETER EventId
        ID події (за замовчуванням 1000).
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')]
        [string]$EntryType = 'Information',
        [int]$EventId = 1000
    )
    $source = "SysAdminToolkit"
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
        }
        Write-EventLog -LogName Application -Source $source -EventId $EventId -EntryType $EntryType -Message $Message
    } catch {
        # Якщо немає прав на створення джерела — тихий fallback
        Write-TkLog "EventLog fallback: $Message" -Level INFO
    }
}

# ============================================================
#  Перевірка ролі
# ============================================================

function Get-TkUserRole {
    <#
        .SYNOPSIS
        Повертає поточну роль користувача з Config/Roles.json.
    #>
    $rolesPath = Join-Path $script:ToolkitRoot "Config\Roles.json"
    if (-not (Test-Path $rolesPath)) { return "Admin" }
    try {
        $rolesData = Get-Content $rolesPath -Encoding UTF8 | ConvertFrom-Json
        # Перевіряємо чи поточний користувач адмін
        $isAdmin = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) { return "Admin" }
        $defaultRole = if ($rolesData.DefaultRole) { $rolesData.DefaultRole } else { "Operator" }
        return $defaultRole
    } catch {
        return "Admin"
    }
}

function Test-TkRoleAccess {
    <#
        .SYNOPSIS
        Перевіряє чи поточна роль має доступ до категорії.
        .PARAMETER Category
        Назва категорії для перевірки.
    #>
    param([Parameter(Mandatory=$true)][string]$Category)
    $rolesPath = Join-Path $script:ToolkitRoot "Config\Roles.json"
    if (-not (Test-Path $rolesPath)) { return $true }
    try {
        $rolesData = Get-Content $rolesPath -Encoding UTF8 | ConvertFrom-Json
        $role = Get-TkUserRole
        $roleConfig = $rolesData.Roles.$role
        if ($null -eq $roleConfig) { return $true }
        $allowed = $roleConfig.AllowedCategories
        if ($allowed -contains "*" -or $allowed -contains $Category) { return $true }
        return $false
    } catch {
        return $true
    }
}

Export-ModuleMember -Function Get-ToolkitRoot, Get-ToolkitConfig, Get-TkHostsList, `
    ConvertFrom-ParamString, Assert-Administrator, Test-ComputerOnline, `
    Write-TkLog, Invoke-WithRetry, Export-TkReport, ConvertTo-TkResult, Send-TkEmail, `
    Show-TkNotification, Invoke-TkRemote, Get-TkCredential, Test-TkPrerequisite, `
    ConvertTo-TkHtmlDashboard, Write-TkEventLog, Get-TkUserRole, Test-TkRoleAccess
