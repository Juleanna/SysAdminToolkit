$script:ToolkitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path $PSCommandPath -Parent))
$script:ConfigPath = Join-Path $script:ToolkitRoot "Config\ToolkitConfig.json"

function Get-ToolkitRoot {
    <#
        .SYNOPSIS
        Возвращает корень набора скриптов (папка SysAdminToolkit).
    #>
    return $script:ToolkitRoot
}

function Get-ToolkitConfig {
    <#
        .SYNOPSIS
        Загружает ToolkitConfig.json с дефолтами.
    #>
    $defaults = [pscustomobject]@{
        CompanyName       = "MyCompany"
        DefaultBackupPath = "D:\Backups"
        Subnet            = "192.168.1."
        Description       = "SysAdminToolkit v5.0"
    }

    if (-not (Test-Path $script:ConfigPath)) {
        return $defaults
    }

    try {
        $cfg = Get-Content -Path $script:ConfigPath -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $defaults
    }

    foreach ($name in $defaults.PSObject.Properties.Name) {
        if ($null -eq $cfg.$name -or ($cfg.$name -is [string] -and [string]::IsNullOrWhiteSpace($cfg.$name))) {
            $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $defaults.$name -Force
        }
    }

    return $cfg
}

function ConvertFrom-ParamString {
    <#
        .SYNOPSIS
        Преобразует строку вида "Param1=Value1;Param2=Value2" в Hashtable для сплаттинга параметров.
    #>
    param([string]$ParamString)

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($ParamString)) {
        return $map
    }

    $parts = $ParamString -split ';' | Where-Object { $_.Trim() }
    foreach ($part in $parts) {
        if ($part -notmatch '=') { continue }
        $kv = $part.Split('=', 2)
        $key = $kv[0].Trim()
        $val = $kv[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $val
        }
    }
    return $map
}

Export-ModuleMember -Function Get-ToolkitRoot, Get-ToolkitConfig, ConvertFrom-ParamString
