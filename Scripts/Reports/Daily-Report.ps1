<#
.SYNOPSIS
    Щоденний зведений звіт стану системи.
.DESCRIPTION
    Збирає: диски, сервіси, перезавантаження, помилки, Defender, аптайм.
    Може надсилати у Telegram, Email або зберігати як HTML.
.PARAMETER SendTelegram
    Надіслати у Telegram.
.PARAMETER SendEmail
    Надіслати на email.
.PARAMETER ExportHtml
    Зберегти як HTML.
.EXAMPLE
    .\Daily-Report.ps1 -ExportHtml -SendTelegram
#>
param(
    [switch]$SendTelegram,
    [switch]$SendEmail,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig
$report = [System.Text.StringBuilder]::new()
$sections = [System.Collections.ArrayList]::new()

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Щоденний звіт — $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Аптайм
$os = Get-CimInstance Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
$uptimeStr = "{0}д {1:hh\:mm}" -f [int]$uptime.TotalDays, $uptime
[void]$report.AppendLine("Аптайм: $uptimeStr")
Write-Host "Аптайм: $uptimeStr" -ForegroundColor White

# Диски
Write-Host "`n--- Дисковий простір ---" -ForegroundColor Cyan
$disks = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    $pct = if ($_.Size -gt 0) { [math]::Round(($_.Size - $_.SizeRemaining) / $_.Size * 100, 1) } else { 0 }
    $color = if ($pct -ge $cfg.DiskSpaceCriticalPercent) { "Red" } elseif ($pct -ge $cfg.DiskSpaceWarningPercent) { "Yellow" } else { "Green" }
    $freeGB = [math]::Round($_.SizeRemaining / 1GB, 1)
    Write-Host "  $($_.DriveLetter): $pct% зайнято, вільно $freeGB ГБ" -ForegroundColor $color
    [PSCustomObject]@{ Диск="$($_.DriveLetter):"; Зайнято="$pct%"; Вільно_ГБ=$freeGB }
}
[void]$sections.Add(@{ Title="Дисковий простір"; Data=$disks; Status=if($disks | Where-Object { [double]($_.Зайнято -replace '%','') -ge $cfg.DiskSpaceCriticalPercent }){"error"}else{"ok"} })

# Критичні сервіси
Write-Host "`n--- Критичні сервіси ---" -ForegroundColor Cyan
$svcData = foreach ($svcName in $cfg.CriticalServices) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  $($svc.DisplayName): $($svc.Status)" -ForegroundColor $color
        [PSCustomObject]@{ Сервіс=$svc.DisplayName; Статус="$($svc.Status)" }
    }
}
$stoppedSvc = @($svcData | Where-Object { $_.Статус -ne 'Running' })
[void]$sections.Add(@{ Title="Критичні сервіси"; Data=$svcData; Status=if($stoppedSvc.Count -gt 0){"error"}else{"ok"} })

# Помилки за 24 год
Write-Host "`n--- Помилки за 24 години ---" -ForegroundColor Cyan
try {
    $errCount = (Get-WinEvent -FilterHashtable @{ LogName='System'; Level=2; StartTime=(Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue | Measure-Object).Count
    $critCount = (Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1; StartTime=(Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "  Критичних: $critCount, Помилок: $errCount" -ForegroundColor $(if($critCount -gt 0){"Red"}elseif($errCount -gt 5){"Yellow"}else{"Green"})
    [void]$report.AppendLine("Помилки 24г: Critical=$critCount, Error=$errCount")
} catch { Write-Host "  Не вдалося отримати." -ForegroundColor Gray }

# Defender
Write-Host "`n--- Windows Defender ---" -ForegroundColor Cyan
try {
    $defender = Get-MpComputerStatus -ErrorAction Stop
    $rtColor = if ($defender.RealTimeProtectionEnabled) { "Green" } else { "Red" }
    Write-Host "  Реальний час: $(if($defender.RealTimeProtectionEnabled){'Увімкнено'}else{'Вимкнено'})" -ForegroundColor $rtColor
    $sigAge = $defender.AntivirusSignatureAge
    Write-Host "  Вік сигнатур: $sigAge днів" -ForegroundColor $(if($sigAge -gt 3){"Yellow"}else{"Green"})
} catch { Write-Host "  Defender недоступний." -ForegroundColor Gray }

# Перезавантаження
$rebootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$reboot = Test-Path $rebootKey
Write-Host "`nПерезавантаження потрібне: $(if($reboot){'ТАК'}else{'Ні'})" -ForegroundColor $(if($reboot){"Red"}else{"Green"})
[void]$report.AppendLine("Перезавантаження: $(if($reboot){'Потрібне'}else{'Не потрібне'})")

# Telegram
if ($SendTelegram) {
    try {
        $tgPath = Join-Path (Get-ToolkitRoot) "Config\Telegram.json"
        $tgCfg = Get-Content $tgPath -Encoding UTF8 | ConvertFrom-Json
        $token = if ($tgCfg.BotToken) { $tgCfg.BotToken } else { $env:SYSADMINTK_BOTTOKEN }
        if ($token -and $tgCfg.ChatID) {
            $text = "Щоденний звіт $env:COMPUTERNAME`n$(Get-Date -Format 'yyyy-MM-dd HH:mm')`n`n$($report.ToString())"
            $body = @{ chat_id = $tgCfg.ChatID; text = $text }
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body $body | Out-Null
            Write-Host "`nЗвіт надіслано у Telegram." -ForegroundColor Green
        }
    } catch { Write-Host "Помилка Telegram: $($_.Exception.Message)" -ForegroundColor Red }
}

# Email
if ($SendEmail) {
    Send-TkEmail -Subject "Щоденний звіт $env:COMPUTERNAME $(Get-Date -Format 'yyyy-MM-dd')" -Body $report.ToString()
}

# HTML
if ($ExportHtml) {
    $path = Join-Path (Get-ToolkitRoot) "Reports\DailyReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    ConvertTo-TkHtmlDashboard -Sections $sections -OutputPath $path -DashboardTitle "Щоденний звіт — $env:COMPUTERNAME"
    Write-Host "`nHTML-звіт: $path" -ForegroundColor Green
}

Write-TkLog "Daily-Report: згенеровано" -Level INFO
