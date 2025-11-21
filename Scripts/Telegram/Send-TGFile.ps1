. "$PSScriptRoot\..\Utils\ToolkitCommon.psm1"

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    [string]$Caption = "Файл"
)

if (-not (Test-Path $FilePath)) {
    Write-Error "Файл не найден: $FilePath"
    exit 1
}

$configPath = Join-Path (Get-ToolkitRoot) "Config\Telegram.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Конфиг Telegram не найден: $configPath"
    exit 1
}

$config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
if (-not $config.Enabled) {
    Write-Host "Telegram отключен в конфиге."
    exit
}

$token = if ($env:SYSADMINTK_BOTTOKEN) { $env:SYSADMINTK_BOTTOKEN } else { $config.BotToken }
if (-not $token) {
    Write-Error "Не задан токен бота (переменная SYSADMINTK_BOTTOKEN или BotToken в конфиге)."
    exit 1
}

$chatId = $config.ChatID
$uri = "https://api.telegram.org/bot$token/sendDocument"

$form = @{
    chat_id  = $chatId
    caption  = $Caption
    document = Get-Item $FilePath
}

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Form $form -ErrorAction Stop
    if (-not $response.ok) {
        throw "Telegram API error: $($response.description)"
    }
    Write-Host "Файл отправлен в Telegram: $FilePath"
} catch {
    Write-Error "Не удалось отправить файл: $($_.Exception.Message)"
    exit 1
}
