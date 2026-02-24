<#
.SYNOPSIS
    Надсилає форматоване сповіщення в Telegram з рівнем критичності.

.DESCRIPTION
    Формує повідомлення з емодзі-префіксом залежно від рівня (Info/Warning/Critical),
    додає ім'я комп'ютера, заголовок та мітку часу. Надсилає через Telegram Bot API
    за допомогою Invoke-RestMethod. Конфігурація (BotToken, ChatID) зчитується
    з Config/Telegram.json. Якщо токен у конфігу порожній, використовується
    змінна оточення SYSADMINTK_BOTTOKEN.

.PARAMETER Level
    Рівень критичності повідомлення: Info, Warning або Critical.
    Визначає емодзі-префікс повідомлення.

.PARAMETER Title
    Заголовок сповіщення (обов'язковий параметр).

.PARAMETER Message
    Текст повідомлення (обов'язковий параметр).

.EXAMPLE
    .\Send-TGAlert.ps1 -Level Info -Title "Бекап" -Message "Резервне копіювання завершено успішно"
    Надсилає інформаційне сповіщення з префіксом ℹ️.

.EXAMPLE
    .\Send-TGAlert.ps1 -Level Warning -Title "Диск" -Message "Диск C: заповнено на 85%"
    Надсилає попередження з префіксом ⚠️.

.EXAMPLE
    .\Send-TGAlert.ps1 -Level Critical -Title "Сервер" -Message "Сервер DB-01 не відповідає"
    Надсилає критичне сповіщення з префіксом 🚨.
#>

param(
    [ValidateSet('Info','Warning','Critical')]
    [string]$Level = 'Info',

    [Parameter(Mandatory=$true)]
    [string]$Title,

    [Parameter(Mandatory=$true)]
    [string]$Message
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Send-TGAlert: підготовка сповіщення [$Level] '$Title'" -Level INFO

# Зчитування конфігурації Telegram
$configPath = Join-Path (Get-ToolkitRoot) "Config\Telegram.json"

if (-not (Test-Path $configPath)) {
    Write-Host "[ПОМИЛКА] Конфіг Telegram не знайдено: $configPath" -ForegroundColor Red
    Write-TkLog "Send-TGAlert: конфіг Telegram не знайдено: $configPath" -Level ERROR
    exit 1
}

try {
    $tgConfig = Get-Content $configPath -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося прочитати конфіг Telegram: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Send-TGAlert: помилка читання конфігу: $($_.Exception.Message)" -Level ERROR
    exit 1
}

# Визначення токена: спочатку конфіг, потім змінна оточення
$token = $tgConfig.BotToken
if ([string]::IsNullOrWhiteSpace($token)) {
    $token = $env:SYSADMINTK_BOTTOKEN
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host "[ПОМИЛКА] Токен бота не задано. Вкажіть BotToken у Config/Telegram.json або встановіть змінну SYSADMINTK_BOTTOKEN." -ForegroundColor Red
    Write-TkLog "Send-TGAlert: токен бота не знайдено" -Level ERROR
    exit 1
}

$chatId = $tgConfig.ChatID
if ([string]::IsNullOrWhiteSpace($chatId)) {
    Write-Host "[ПОМИЛКА] ChatID не задано в конфігурації Telegram." -ForegroundColor Red
    Write-TkLog "Send-TGAlert: ChatID не задано" -Level ERROR
    exit 1
}

# Емодзі-префікс залежно від рівня
$emoji = switch ($Level) {
    'Info'     { [char]::ConvertFromUtf32(0x2139) + [char]::ConvertFromUtf32(0xFE0F) }   # ℹ️
    'Warning'  { [char]::ConvertFromUtf32(0x26A0) + [char]::ConvertFromUtf32(0xFE0F) }   # ⚠️
    'Critical' { [char]::ConvertFromUtf32(0x1F6A8) }                                       # 🚨
}

$levelLabel = switch ($Level) {
    'Info'     { 'IНФО' }
    'Warning'  { 'УВАГА' }
    'Critical' { 'КРИТИЧНО' }
}

# Формування повідомлення
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$formattedText = @"
$emoji ${levelLabel}: $Title

$Message

$([char]::ConvertFromUtf32(0x1F4BB)) $env:COMPUTERNAME
$([char]::ConvertFromUtf32(0x1F552)) $timestamp
"@

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Надсилання Telegram-сповіщення" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$levelColor = switch ($Level) {
    'Info'     { 'Cyan' }
    'Warning'  { 'Yellow' }
    'Critical' { 'Red' }
}

Write-Host "  Рівень:     $Level" -ForegroundColor $levelColor
Write-Host "  Заголовок:  $Title" -ForegroundColor White
Write-Host "  Комп'ютер:  $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Час:        $timestamp" -ForegroundColor Gray
Write-Host ""

# Надсилання через Telegram Bot API
$uri = "https://api.telegram.org/bot$token/sendMessage"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body @{
        chat_id    = $chatId
        text       = $formattedText
        parse_mode = "HTML"
    } -ErrorAction Stop

    if ($response.ok) {
        Write-Host "  [OK] Сповіщення успішно надіслано в Telegram." -ForegroundColor Green
        Write-TkLog "Send-TGAlert: сповіщення [$Level] '$Title' надіслано успішно" -Level INFO
    } else {
        throw "Telegram API повернув помилку: $($response.description)"
    }
} catch {
    Write-Host "  [ПОМИЛКА] Не вдалося надіслати сповіщення: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Send-TGAlert: помилка надсилання — $($_.Exception.Message)" -Level ERROR
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
