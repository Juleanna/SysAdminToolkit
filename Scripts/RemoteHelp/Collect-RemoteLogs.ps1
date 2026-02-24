param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$tempName = "RemoteLogs_$((Get-Random))"
$remoteTemp = "C:\Windows\Temp\$tempName"
$localDest = Join-Path (Get-ToolkitRoot) "RemoteLogs_$ComputerName.zip"

Write-Host "Експортуємо журнали з $ComputerName..." -ForegroundColor Cyan

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($remoteTemp)
        New-Item -ItemType Directory -Path $remoteTemp -Force | Out-Null
        wevtutil epl System (Join-Path $remoteTemp 'System.evtx')
        wevtutil epl Application (Join-Path $remoteTemp 'Application.evtx')
        Compress-Archive -Path (Join-Path $remoteTemp '*') -DestinationPath ("$remoteTemp.zip") -Force
    } -ArgumentList $remoteTemp -ErrorAction Stop

    Copy-Item "\\$ComputerName\C$\Windows\Temp\$tempName.zip" $localDest -Force -ErrorAction Stop

    Write-Host "Архів отримано: $localDest" -ForegroundColor Green
} catch {
    Write-Error "Помилка при зборі логів: $($_.Exception.Message)"
    exit 1
} finally {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($remoteTemp)
        Remove-Item "$remoteTemp" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$remoteTemp.zip" -Force -ErrorAction SilentlyContinue
    } -ArgumentList $remoteTemp -ErrorAction SilentlyContinue
}
