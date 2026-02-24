param(
    [Parameter(Mandatory=$true)]
    [string]$Text
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$configPath = Join-Path (Get-ToolkitRoot) "Config\Telegram.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Конфіг Telegram не знайдено: $configPath"
    exit 1
}

$config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json

if (-not $config.Enabled) {
    Write-Host "Telegram вимкнено в конфігу."
    exit
}

$token = if ($env:SYSADMINTK_BOTTOKEN) { $env:SYSADMINTK_BOTTOKEN } else { $config.BotToken }
if (-not $token) {
    Write-Error "Не задано токен бота (змінна SYSADMINTK_BOTTOKEN або BotToken в конфігу)."
    exit 1
}

$chatId = $config.ChatID
$uri = "https://api.telegram.org/bot$token/sendMessage"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body @{
        chat_id = $chatId
        text    = $Text
    } -ErrorAction Stop
    if (-not $response.ok) {
        throw "Telegram API error: $($response.description)"
    }
    Write-Host "Повідомлення надіслано в Telegram." -ForegroundColor Green
} catch {
    Write-Error "Не вдалося надіслати повідомлення: $($_.Exception.Message)"
    exit 1
}
