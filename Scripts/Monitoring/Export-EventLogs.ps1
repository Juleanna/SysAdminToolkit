param(
    [string]$LogName = 'System',
    [int]$Newest = 200,
    [string]$OutputPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-ToolkitRoot) ("Events_$($env:COMPUTERNAME)_$LogName.csv")
}

try {
    $events = Get-WinEvent -LogName $LogName -MaxEvents $Newest -ErrorAction Stop
} catch {
    Write-Error "Не вдалося отримати журнал '$LogName': $($_.Exception.Message)"
    exit 1
}

if (-not $events) {
    Write-Host "Подій не знайдено." -ForegroundColor Yellow
    exit 0
}

$events |
    Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Подій експортовано: $(@($events).Count) -> $OutputPath" -ForegroundColor Green
