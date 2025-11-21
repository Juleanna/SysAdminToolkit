. "$PSScriptRoot\..\Utils\ToolkitCommon.psm1"

param(
    [string]$Subnet
)

if (-not $Subnet) {
    $Subnet = (Get-ToolkitConfig).Subnet
}

Write-Host "Сканируем подсеть $Subnet* ..."

1..254 | ForEach-Object {
    $ip = "$Subnet$_"
    if (Test-Connection -Count 1 -Quiet -ComputerName $ip) {
        Write-Host "$ip — ответил"
    }
}
