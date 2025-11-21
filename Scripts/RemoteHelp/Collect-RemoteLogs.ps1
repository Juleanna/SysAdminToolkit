param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

$tempName = "RemoteLogs_$((Get-Random))"
$remoteTemp = "C:\Windows\Temp\$tempName"

Write-Host "Экспортируем журналы на $ComputerName в $remoteTemp..."

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($remoteTemp)
        New-Item -ItemType Directory -Path $remoteTemp -Force | Out-Null
        wevtutil epl System (Join-Path $remoteTemp 'System.evtx')
        wevtutil epl Application (Join-Path $remoteTemp 'Application.evtx')
        Compress-Archive -Path (Join-Path $remoteTemp '*') -DestinationPath ("$remoteTemp.zip") -Force
    } -ArgumentList $remoteTemp -ErrorAction Stop

    $localDest = ".\RemoteLogs_$ComputerName.zip"
    Copy-Item "\\$ComputerName\C$\Windows\Temp\$tempName.zip" $localDest -Force -ErrorAction Stop

    Write-Host "Архив получен: $localDest"
} catch {
    Write-Error "Ошибка при сборе логов: $($_.Exception.Message)"
} finally {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($remoteTemp)
        Remove-Item "$remoteTemp" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$remoteTemp.zip" -Force -ErrorAction SilentlyContinue
    } -ArgumentList $remoteTemp -ErrorAction SilentlyContinue
}
