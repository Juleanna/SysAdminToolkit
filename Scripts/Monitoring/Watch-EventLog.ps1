<#
.SYNOPSIS
    Моніторить журнал подій Windows у реальному часі з періодичним опитуванням.
.DESCRIPTION
    Періодично опитує вказаний журнал подій Windows через Get-WinEvent,
    фільтруючи за рівнем (Level). Відображає нові події з кольоровим
    кодуванням за рівнем критичності. При увімкненому прапорці -SendTelegram
    надсилає сповіщення через Telegram API (налаштування з Config/Telegram.json).
.PARAMETER LogName
    Назва журналу подій для моніторингу. За замовчуванням: "System".
.PARAMETER Level
    Рівень критичності подій (1=Critical, 2=Error, 3=Warning, 4=Information).
    За замовчуванням: 1 (Critical). Фільтрує події з рівнем <= вказаного.
.PARAMETER IntervalSec
    Інтервал між опитуваннями в секундах. За замовчуванням: 60.
.PARAMETER MaxIterations
    Максимальна кількість ітерацій опитування. За замовчуванням: 10.
.PARAMETER SendTelegram
    Якщо вказано, надсилає сповіщення про критичні події в Telegram.
.EXAMPLE
    .\Watch-EventLog.ps1
    Моніторить Critical-події в System журналі з інтервалом 60 сек, 10 ітерацій.
.EXAMPLE
    .\Watch-EventLog.ps1 -LogName "Application" -Level 2 -IntervalSec 30 -SendTelegram
    Моніторить Critical та Error події в Application журналі кожні 30 сек з Telegram.
#>
param(
    [string]$LogName = "System",

    [int]$Level = 1,

    [int]$IntervalSec = 60,

    [int]$MaxIterations = 10,

    [switch]$SendTelegram
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск Watch-EventLog (Log=$LogName, Level=$Level, Interval=$IntervalSec, MaxIter=$MaxIterations, Telegram=$SendTelegram)" -Level INFO

# --- Функція для надсилання в Telegram ---
function Send-TelegramAlert {
    param(
        [string]$Text,
        [string]$Token,
        [string]$ChatId
    )

    if (-not $Token -or -not $ChatId) { return }

    $uri = "https://api.telegram.org/bot$Token/sendMessage"
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Body @{
            chat_id    = $ChatId
            text       = $Text
            parse_mode = 'HTML'
        } -ErrorAction Stop | Out-Null
        Write-TkLog "Telegram-сповіщення надіслано" -Level DEBUG
    } catch {
        Write-TkLog "Помилка Telegram: $($_.Exception.Message)" -Level WARN
        Write-Host "  [Telegram помилка: $($_.Exception.Message)]" -ForegroundColor DarkYellow
    }
}

# --- Конвертація рівня у текст ---
function Get-LevelName {
    param([int]$LevelId)
    switch ($LevelId) {
        1 { return "Critical" }
        2 { return "Error" }
        3 { return "Warning" }
        4 { return "Information" }
        5 { return "Verbose" }
        default { return "Level$LevelId" }
    }
}

function Get-LevelColor {
    param([int]$LevelId)
    switch ($LevelId) {
        1 { return "Red" }
        2 { return "Red" }
        3 { return "Yellow" }
        4 { return "Cyan" }
        default { return "Gray" }
    }
}

try {
    # --- Конфігурація Telegram ---
    $tgToken = $null
    $tgChatId = $null

    if ($SendTelegram) {
        $tgConfigPath = Join-Path (Get-ToolkitRoot) "Config\Telegram.json"
        if (-not (Test-Path $tgConfigPath)) {
            Write-Host "Конфіг Telegram не знайдено: $tgConfigPath" -ForegroundColor Red
            Write-Host "Telegram-сповіщення вимкнено для цієї сесії." -ForegroundColor Yellow
            Write-TkLog "Telegram.json не знайдено, сповіщення вимкнено" -Level WARN
            $SendTelegram = $false
        } else {
            try {
                $tgConfig = Get-Content $tgConfigPath -Encoding UTF8 | ConvertFrom-Json
                if (-not $tgConfig.Enabled) {
                    Write-Host "Telegram вимкнено в конфігурації." -ForegroundColor Yellow
                    $SendTelegram = $false
                } else {
                    $tgToken = if ($env:SYSADMINTK_BOTTOKEN) { $env:SYSADMINTK_BOTTOKEN } else { $tgConfig.BotToken }
                    $tgChatId = $tgConfig.ChatID
                    if (-not $tgToken -or -not $tgChatId) {
                        Write-Host "Telegram: не задано BotToken або ChatID." -ForegroundColor Red
                        $SendTelegram = $false
                    } else {
                        Write-Host "Telegram-сповіщення увімкнено." -ForegroundColor Green
                    }
                }
            } catch {
                Write-Host "Помилка читання Telegram.json: $($_.Exception.Message)" -ForegroundColor Red
                $SendTelegram = $false
            }
        }
    }

    # --- Заголовок ---
    $levelNames = @()
    for ($l = 1; $l -le $Level; $l++) { $levelNames += Get-LevelName $l }
    $levelStr = $levelNames -join ', '

    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "         МОНIТОРИНГ ЖУРНАЛУ ПОДIЙ" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Журнал:      $LogName" -ForegroundColor Cyan
    Write-Host "Рівні:       $levelStr (Level <= $Level)" -ForegroundColor Cyan
    Write-Host "Інтервал:    $IntervalSec сек" -ForegroundColor Cyan
    Write-Host "Ітерацій:    $MaxIterations" -ForegroundColor Cyan
    Write-Host "Telegram:    $(if ($SendTelegram) { 'Увімкнено' } else { 'Вимкнено' })" -ForegroundColor $(if ($SendTelegram) { 'Green' } else { 'DarkGray' })
    Write-Host "Старт:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Натисніть Ctrl+C для зупинки`n" -ForegroundColor DarkGray

    # --- Початкова мітка часу ---
    $lastCheck = Get-Date
    $totalEventsFound = 0

    for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
        $currentTime = Get-Date
        Write-Host "[Ітерація $iteration/$MaxIterations | $(Get-Date -Format 'HH:mm:ss')] Перевірка нових подій..." -ForegroundColor DarkCyan

        try {
            # --- Фільтр подій ---
            $filterXml = @"
<QueryList>
  <Query Id="0" Path="$LogName">
    <Select Path="$LogName">*[System[(Level&lt;=$Level) and TimeCreated[@SystemTime&gt;='$($lastCheck.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))']]]</Select>
  </Query>
</QueryList>
"@

            $events = @()
            try {
                $events = @(Get-WinEvent -FilterXml $filterXml -ErrorAction Stop)
            } catch [Exception] {
                if ($_.Exception.Message -notmatch 'No events were found') {
                    throw
                }
            }

            if ($events.Count -gt 0) {
                Write-Host "  Знайдено подій: $($events.Count)" -ForegroundColor White
                $totalEventsFound += $events.Count

                foreach ($event in $events) {
                    $evtLevel = $event.Level
                    $evtColor = Get-LevelColor $evtLevel
                    $evtLevelName = Get-LevelName $evtLevel
                    $evtTime = $event.TimeCreated.ToString('HH:mm:ss')
                    $evtSource = $event.ProviderName
                    $evtId = $event.Id
                    $evtMsg = if ($event.Message) {
                        $firstLine = $event.Message.Split("`n")[0].Trim()
                        if ($firstLine.Length -gt 100) {
                            $firstLine.Substring(0, 100).Trim() + '...'
                        } else {
                            $firstLine
                        }
                    } else {
                        '(без повідомлення)'
                    }

                    $line = "  [$evtLevelName] $evtTime | ID:$evtId | $evtSource"
                    Write-Host $line -ForegroundColor $evtColor
                    Write-Host "    $evtMsg" -ForegroundColor Gray

                    Write-TkLog "EventWatch: [$evtLevelName] $LogName EventID=$evtId Source=$evtSource" -Level $(if ($evtLevel -le 2) { 'WARN' } else { 'INFO' })

                    # --- Telegram для критичних ---
                    if ($SendTelegram -and $evtLevel -le 2) {
                        $tgText = "<b>Event Alert</b>`n" +
                                  "<b>Level:</b> $evtLevelName`n" +
                                  "<b>Log:</b> $LogName`n" +
                                  "<b>Source:</b> $evtSource`n" +
                                  "<b>EventID:</b> $evtId`n" +
                                  "<b>Time:</b> $evtTime`n" +
                                  "<b>Host:</b> $($env:COMPUTERNAME)`n" +
                                  "<b>Message:</b> $evtMsg"
                        Send-TelegramAlert -Text $tgText -Token $tgToken -ChatId $tgChatId
                    }
                }
            } else {
                Write-Host "  Нових подій немає." -ForegroundColor DarkGray
            }

        } catch {
            Write-Host "  Помилка опитування: $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Watch-EventLog помилка ітерації $iteration : $($_.Exception.Message)" -Level ERROR
        }

        $lastCheck = $currentTime

        # --- Очікування (окрім останньої ітерації) ---
        if ($iteration -lt $MaxIterations) {
            Write-Host "  Наступна перевірка через $IntervalSec сек...`n" -ForegroundColor DarkGray
            Start-Sleep -Seconds $IntervalSec
        }
    }

    # --- Підсумок ---
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                     ПIДСУМОК" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Ітерацій виконано:  $MaxIterations" -ForegroundColor White
    Write-Host "Всього подій:       " -NoNewline
    if ($totalEventsFound -gt 0) {
        Write-Host "$totalEventsFound" -ForegroundColor Red
    } else {
        Write-Host "$totalEventsFound" -ForegroundColor Green
    }
    Write-Host "Завершено:          $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White

    Write-TkLog "Watch-EventLog завершено. Знайдено подій: $totalEventsFound" -Level INFO

} catch {
    $errMsg = "Критична помилка Watch-EventLog: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
