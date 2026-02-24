param(
    [string]$OutputPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-ToolkitRoot) ("PC_Inventory_$($env:COMPUTERNAME).json")
}

$pc = $env:COMPUTERNAME

function Safe-GetCim {
    param($Class)
    try { Get-CimInstance $Class -ErrorAction Stop } catch { $null }
}

$os     = Safe-GetCim Win32_OperatingSystem
$cs     = Safe-GetCim Win32_ComputerSystem
$cpu    = Safe-GetCim Win32_Processor
$gpu    = Safe-GetCim Win32_VideoController
$bios   = Safe-GetCim Win32_BIOS
$nics   = Safe-GetCim Win32_NetworkAdapterConfiguration
$disks  = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
$ipCfg  = Get-NetIPConfiguration -ErrorAction SilentlyContinue
$ipAddresses = $ipCfg |
    ForEach-Object { $_.IPv4Address } |
    Where-Object { $_ -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
$gateway = $ipCfg |
    ForEach-Object { $_.IPv4DefaultGateway } |
    Where-Object { $_ } |
    Select-Object -First 1 -ExpandProperty NextHop

$data = [pscustomobject]@{
    ComputerName    = $pc
    Company         = $cfg.CompanyName
    OS              = $os?.Caption
    OSVersion       = $os?.Version
    Manufacturer    = $cs?.Manufacturer
    Model           = $cs?.Model
    CPU             = $cpu?.Name
    Cores           = $cpu?.NumberOfCores
    RAM_GB          = if ($cs) { [math]::Round($cs.TotalPhysicalMemory/1GB,2) } else { $null }
    GPU             = if ($gpu) { ($gpu | Select-Object -ExpandProperty Name) -join ', ' } else { '' }
    BIOSVersion     = $bios?.SMBIOSBIOSVersion
    SerialNumber    = $bios?.SerialNumber
    Disks           = if ($disks){ $disks | Select-Object FriendlyName,Size } else { @() }
    MACAddresses    = if ($nics){ $nics | Where-Object { $_.MACAddress } | Select-Object -ExpandProperty MACAddress } else { @() }
    IPAddresses     = $ipAddresses
    DefaultGateway  = $gateway
    Date            = Get-Date
}

$data | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Состояние сохранено в $OutputPath"
