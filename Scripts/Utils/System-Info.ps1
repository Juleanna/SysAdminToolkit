<#
.SYNOPSIS
    Комплексний звіт про стан системи на одній сторінці.

.DESCRIPTION
    Збирає та відображає детальну інформацію про систему: версія ОС, ім'я
    комп'ютера, домен, час роботи (uptime), процесор (Get-CimInstance Win32_Processor),
    оперативна пам'ять (загальна/вільна), дисковий простір, IP-адреси, поточні
    сеанси користувачів, статус оновлень Windows та Defender.
    Інформація виводиться у консоль із кольоровими заголовками секцій.
    За допомогою параметра -ExportHtml можна зберегти звіт у HTML-файл.

.PARAMETER ExportHtml
    Якщо вказано, зберігає звіт у HTML-файл у папку Reports тулкіту.

.EXAMPLE
    .\System-Info.ps1
    Виводить повний звіт про систему у консоль.

.EXAMPLE
    .\System-Info.ps1 -ExportHtml
    Виводить інформацію у консоль та зберігає HTML-звіт.
#>

param(
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig

Write-TkLog "System-Info: запуск збору інформації про систему" -Level INFO

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("  " + "-" * 60) -ForegroundColor DarkGray
}

function Write-Field {
    param([string]$Label, [string]$Value, [string]$ValueColor = 'White')
    Write-Host ("  {0,-28} " -f $Label) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $ValueColor
}

Write-Host ""
Write-Host ("=" * 64) -ForegroundColor DarkCyan
Write-Host "     СИСТЕМНА IНФОРМАЦIЯ  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ("=" * 64) -ForegroundColor DarkCyan

$reportData = @()

# --- Загальна інформація ---
Write-Section "ЗАГАЛЬНА IНФОРМАЦIЯ"

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

    Write-Field "Ім'я комп'ютера:" $env:COMPUTERNAME 'Yellow'
    Write-Field "Операційна система:" $os.Caption
    Write-Field "Версія:" "$($os.Version) (Build $($os.BuildNumber))"

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0} днів, {1} год, {2} хв" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    $uptimeColor = if ($uptime.Days -gt 30) { 'Red' } elseif ($uptime.Days -gt 7) { 'Yellow' } else { 'Green' }
    Write-Field "Аптайм:" $uptimeStr $uptimeColor

    Write-Field "Домен/Робоча група:" $cs.Domain
    Write-Field "Тип приєднання:" $(if ($cs.PartOfDomain) { "Домен" } else { "Робоча група" })

    $reportData += [pscustomobject]@{ Секція = "ОС"; Параметр = "Комп'ютер"; Значення = $env:COMPUTERNAME }
    $reportData += [pscustomobject]@{ Секція = "ОС"; Параметр = "ОС"; Значення = $os.Caption }
    $reportData += [pscustomobject]@{ Секція = "ОС"; Параметр = "Версія"; Значення = "$($os.Version) (Build $($os.BuildNumber))" }
    $reportData += [pscustomobject]@{ Секція = "ОС"; Параметр = "Аптайм"; Значення = $uptimeStr }
    $reportData += [pscustomobject]@{ Секція = "ОС"; Параметр = "Домен"; Значення = $cs.Domain }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати загальну інформацію: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання загальних даних: $($_.Exception.Message)" -Level ERROR
}

# --- CPU ---
Write-Section "ПРОЦЕСОР"

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    Write-Field "Модель:" $cpu.Name.Trim()
    Write-Field "Ядер / Потоків:" "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
    Write-Field "Макс. частота:" "$($cpu.MaxClockSpeed) МГц"

    $cpuLoad = $cpu.LoadPercentage
    if ($null -ne $cpuLoad) {
        $loadColor = if ($cpuLoad -gt 80) { 'Red' } elseif ($cpuLoad -gt 50) { 'Yellow' } else { 'Green' }
        Write-Field "Завантаження:" "$cpuLoad%" $loadColor
    }

    $reportData += [pscustomobject]@{ Секція = "CPU"; Параметр = "Модель"; Значення = $cpu.Name.Trim() }
    $reportData += [pscustomobject]@{ Секція = "CPU"; Параметр = "Ядра/Потоки"; Значення = "$($cpu.NumberOfCores)/$($cpu.NumberOfLogicalProcessors)" }
    $reportData += [pscustomobject]@{ Секція = "CPU"; Параметр = "Частота"; Значення = "$($cpu.MaxClockSpeed) МГц" }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати інформацію про CPU: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання даних CPU: $($_.Exception.Message)" -Level ERROR
}

# --- RAM ---
Write-Section "ОПЕРАТИВНА ПАМ'ЯТЬ"

try {
    $osRam = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $totalGB = [math]::Round($osRam.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [math]::Round($osRam.FreePhysicalMemory / 1MB, 2)
    $usedGB = [math]::Round($totalGB - $freeGB, 2)
    $usedPct = [math]::Round(($usedGB / $totalGB) * 100, 1)

    $ramColor = if ($usedPct -gt 90) { 'Red' } elseif ($usedPct -gt 70) { 'Yellow' } else { 'Green' }

    Write-Field "Загальна:" "$totalGB ГБ"
    Write-Field "Використано:" "$usedGB ГБ ($usedPct%)" $ramColor
    Write-Field "Вільна:" "$freeGB ГБ"

    $reportData += [pscustomobject]@{ Секція = "RAM"; Параметр = "Загальна"; Значення = "$totalGB ГБ" }
    $reportData += [pscustomobject]@{ Секція = "RAM"; Параметр = "Використано"; Значення = "$usedGB ГБ ($usedPct%)" }
    $reportData += [pscustomobject]@{ Секція = "RAM"; Параметр = "Вільна"; Значення = "$freeGB ГБ" }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати інформацію про RAM: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання даних RAM: $($_.Exception.Message)" -Level ERROR
}

# --- Дискова підсистема ---
Write-Section "ДИСКОВИЙ ПРОСТIР"

try {
    $warnPct = $cfg.DiskSpaceWarningPercent
    $critPct = $cfg.DiskSpaceCriticalPercent

    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

    foreach ($disk in $disks) {
        $totalDiskGB = [math]::Round($disk.Size / 1GB, 1)
        $freeDiskGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $usedDiskPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)

        $diskColor = if ($usedDiskPct -ge $critPct) { 'Red' } elseif ($usedDiskPct -ge $warnPct) { 'Yellow' } else { 'Green' }

        $barLen = 20
        $filled = [math]::Round($usedDiskPct / 100 * $barLen)
        $bar = "[" + ("#" * $filled) + ("." * ($barLen - $filled)) + "]"

        Write-Host ("  {0,-28} " -f "$($disk.DeviceID) ($totalDiskGB ГБ)") -NoNewline -ForegroundColor Gray
        Write-Host "$bar " -NoNewline -ForegroundColor $diskColor
        Write-Host "$usedDiskPct% зайнято, $freeDiskGB ГБ вільно" -ForegroundColor $diskColor

        $reportData += [pscustomobject]@{
            Секція   = "Диски"
            Параметр = $disk.DeviceID
            Значення = "Всього: ${totalDiskGB} ГБ, Вільно: ${freeDiskGB} ГБ, Зайнято: ${usedDiskPct}%"
        }
    }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати інформацію про диски: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання даних дисків: $($_.Exception.Message)" -Level ERROR
}

# --- Мережа ---
Write-Section "IP-АДРЕСИ"

try {
    $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' }

    foreach ($adapter in $adapters) {
        $ifAlias = $adapter.InterfaceAlias
        Write-Field "${ifAlias}:" "$($adapter.IPAddress)/$($adapter.PrefixLength)"

        $reportData += [pscustomobject]@{
            Секція   = "Мережа"
            Параметр = $ifAlias
            Значення = "$($adapter.IPAddress)/$($adapter.PrefixLength)"
        }
    }

    $defaultGW = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($defaultGW) {
        Write-Field "Шлюз за замовчуванням:" $defaultGW.NextHop 'Yellow'
        $reportData += [pscustomobject]@{ Секція = "Мережа"; Параметр = "Шлюз"; Значення = $defaultGW.NextHop }
    }

    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses } |
        Select-Object -First 1
    if ($dns -and $dns.ServerAddresses) {
        Write-Field "DNS-сервери:" ($dns.ServerAddresses -join ", ")
        $reportData += [pscustomobject]@{ Секція = "Мережа"; Параметр = "DNS"; Значення = ($dns.ServerAddresses -join ", ") }
    }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати мережеву інформацію: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання мережевих даних: $($_.Exception.Message)" -Level ERROR
}

# --- Поточні сеанси користувачів ---
Write-Section "ПОТОЧНI СЕАНСИ КОРИСТУВАЧIВ"

try {
    $queryResult = $null
    try {
        $queryResult = (& query user 2>$null)
    } catch {
        # query user може бути недоступною
    }

    if ($queryResult -and $queryResult.Count -gt 1) {
        $headerLine = $queryResult[0]
        Write-Host "  $headerLine" -ForegroundColor Gray
        Write-Host ("  " + "-" * ($headerLine.Length)) -ForegroundColor DarkGray

        $queryResult | Select-Object -Skip 1 | ForEach-Object {
            $trimmed = $_.Trim()
            if ($trimmed) {
                $sessionColor = if ($trimmed -match 'Active|Актив') { 'Green' } else { 'Yellow' }
                Write-Host "  $trimmed" -ForegroundColor $sessionColor

                $reportData += [pscustomobject]@{
                    Секція   = "Користувачі"
                    Параметр = "Сеанс"
                    Значення = $trimmed
                }
            }
        }
    } else {
        # Резервний метод через CIM
        $logonSessions = Get-CimInstance Win32_LogonSession -ErrorAction SilentlyContinue |
            Where-Object { $_.LogonType -eq 2 -or $_.LogonType -eq 10 }

        if ($logonSessions) {
            foreach ($session in $logonSessions) {
                try {
                    $userObj = Get-CimAssociatedInstance -InputObject $session -ResultClassName Win32_UserAccount -ErrorAction SilentlyContinue
                    if ($userObj) {
                        $logonType = if ($session.LogonType -eq 2) { "Локальний" } else { "RDP" }
                        $startStr = if ($session.StartTime) { $session.StartTime.ToString("yyyy-MM-dd HH:mm") } else { "N/A" }
                        Write-Field "$($userObj.Domain)\$($userObj.Name):" "$logonType, з $startStr"

                        $reportData += [pscustomobject]@{
                            Секція   = "Користувачі"
                            Параметр = "$($userObj.Domain)\$($userObj.Name)"
                            Значення = "$logonType, з $startStr"
                        }
                    }
                } catch {
                    # Пропускаємо сеанси без асоціацій
                }
            }
        } else {
            Write-Host "  Активних інтерактивних сеансів не знайдено." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося отримати дані сеансів: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "System-Info: помилка отримання даних сеансів: $($_.Exception.Message)" -Level ERROR
}

# --- Останнє оновлення Windows ---
Write-Section "ОНОВЛЕННЯ WINDOWS"

try {
    $lastUpdate = Get-HotFix -ErrorAction Stop |
        Sort-Object -Property InstalledOn -Descending -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($lastUpdate -and $lastUpdate.InstalledOn) {
        $daysSince = ((Get-Date) - $lastUpdate.InstalledOn).Days
        $updateColor = if ($daysSince -gt 60) { 'Red' } elseif ($daysSince -gt 30) { 'Yellow' } else { 'Green' }
        Write-Field "Останнє оновлення:" "$($lastUpdate.HotFixID) ($($lastUpdate.InstalledOn.ToString('yyyy-MM-dd')), $daysSince днів тому)" $updateColor

        $reportData += [pscustomobject]@{ Секція = "Оновлення"; Параметр = "Останнє"; Значення = "$($lastUpdate.HotFixID) ($($lastUpdate.InstalledOn.ToString('yyyy-MM-dd')))" }
    } else {
        Write-Field "Останнє оновлення:" "Інформація недоступна" 'Yellow'
    }
} catch {
    Write-Field "Останнє оновлення:" "Не вдалося отримати дані" 'Yellow'
}

# --- Defender ---
Write-Section "WINDOWS DEFENDER"

try {
    $defender = Get-MpComputerStatus -ErrorAction Stop

    $rtColor = if ($defender.RealTimeProtectionEnabled) { 'Green' } else { 'Red' }
    Write-Field "Захист у реальному часі:" $(if ($defender.RealTimeProtectionEnabled) { "Увімкнено" } else { "ВИМКНЕНО" }) $rtColor

    if ($defender.AntivirusSignatureLastUpdated) {
        $sigDays = ((Get-Date) - $defender.AntivirusSignatureLastUpdated).Days
        $sigColor = if ($sigDays -gt 7) { 'Red' } elseif ($sigDays -gt 3) { 'Yellow' } else { 'Green' }
        Write-Field "Оновлення сигнатур:" "$($defender.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm')) ($sigDays днів тому)" $sigColor
    }

    Write-Field "Версія антивірусу:" $defender.AntivirusSignatureVersion

    $reportData += [pscustomobject]@{ Секція = "Defender"; Параметр = "Захист"; Значення = $(if ($defender.RealTimeProtectionEnabled) { "Увімкнено" } else { "Вимкнено" }) }
} catch {
    Write-Field "Статус Defender:" "Не вдалося отримати (можливо, не встановлено)" 'Yellow'
}

Write-Host ""
Write-Host ("=" * 64) -ForegroundColor DarkCyan
Write-Host "  Збір інформації завершено." -ForegroundColor Cyan
Write-Host ("=" * 64) -ForegroundColor DarkCyan
Write-Host ""

# --- Експорт HTML ---
if ($ExportHtml) {
    try {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportPath = Join-Path $reportDir "SystemInfo_${env:COMPUTERNAME}_${timestamp}.html"
        $result = Export-TkReport -Data $reportData -Path $reportPath -Title "Інформація про систему — $env:COMPUTERNAME" -Format HTML
        Write-Host "[OK] HTML-звіт збережено: $result" -ForegroundColor Green
        Write-TkLog "System-Info: HTML-звіт збережено: $result" -Level INFO
    } catch {
        Write-Host "[ПОМИЛКА] Не вдалося експортувати HTML-звіт: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "System-Info: помилка експорту HTML: $($_.Exception.Message)" -Level ERROR
    }
}

Write-TkLog "System-Info: збір інформації про систему завершено" -Level INFO
