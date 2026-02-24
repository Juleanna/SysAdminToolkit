param(
    [string]$OutputPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-ToolkitRoot) ("InstalledSoftware_$($env:COMPUTERNAME).csv")
}

$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = foreach ($path in $paths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}

$apps | Sort-Object DisplayName |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Список установленного ПО записан в $OutputPath"
