param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    [string]$Caption = "Файл"
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if (-not (Test-Path $FilePath)) {
    Write-Error "Файл не знайдено: $FilePath"
    exit 1
}

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
$uri = "https://api.telegram.org/bot$token/sendDocument"

# Сумісність з PowerShell 5.1 (multipart/form-data без -Form)
$fileItem = Get-Item $FilePath
$fileBytes = [System.IO.File]::ReadAllBytes($fileItem.FullName)
$boundary = [System.Guid]::NewGuid().ToString()
$LF = "`r`n"

$bodyLines = @(
    "--$boundary",
    "Content-Disposition: form-data; name=`"chat_id`"$LF",
    $chatId,
    "--$boundary",
    "Content-Disposition: form-data; name=`"caption`"$LF",
    $Caption,
    "--$boundary",
    "Content-Disposition: form-data; name=`"document`"; filename=`"$($fileItem.Name)`"",
    "Content-Type: application/octet-stream$LF"
)

$headerBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join $LF) + $LF)
$footerBytes = [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")
$body = New-Object byte[] ($headerBytes.Length + $fileBytes.Length + $footerBytes.Length)
[System.Buffer]::BlockCopy($headerBytes, 0, $body, 0, $headerBytes.Length)
[System.Buffer]::BlockCopy($fileBytes, 0, $body, $headerBytes.Length, $fileBytes.Length)
[System.Buffer]::BlockCopy($footerBytes, 0, $body, $headerBytes.Length + $fileBytes.Length, $footerBytes.Length)

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -ErrorAction Stop
    if (-not $response.ok) {
        throw "Telegram API error: $($response.description)"
    }
    Write-Host "Файл надіслано в Telegram: $($fileItem.Name)"
} catch {
    Write-Error "Не вдалося надіслати файл: $($_.Exception.Message)"
    exit 1
}
