. "$PSScriptRoot\..\Utils\ToolkitCommon.psm1"

param(
    [string]$LogName = 'System',
    [int]$Newest = 200,
    [string]$OutputPath
)

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-ToolkitRoot) ("Events_$($env:COMPUTERNAME)_$LogName.csv")
}

Get-WinEvent -LogName $LogName -MaxEvents $Newest |
    Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "События выгружены в $OutputPath"
