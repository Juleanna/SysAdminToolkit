param(
    [ValidateSet('Enable','Disable','Toggle')]
    [string]$Mode = 'Toggle'
)

$path = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator privileges required to change USB storage state. Run PowerShell as Administrator."
    exit 1
}

if (-not (Test-Path $path)) {
    Write-Error "USBSTOR service key not found"
    exit 1
}

try {
    $current = (Get-ItemProperty -Path $path -Name 'Start' -ErrorAction Stop).Start
} catch {
    Write-Error "Failed to read current USB storage state: $($_.Exception.Message)"
    exit 1
}

$targetValue = switch ($Mode) {
    'Disable' { 4 }
    'Enable'  { 3 }
    'Toggle'  {
        if ($current -eq 4) { 3 } else { 4 }
    }
}

switch ($Mode) {
    'Disable' { $action = "disabled" }
    'Enable'  { $action = "enabled" }
    'Toggle'  { $action = if ($targetValue -eq 3) { "enabled (toggled)" } else { "disabled (toggled)" } }
}

try {
    Set-ItemProperty -Path $path -Name 'Start' -Value $targetValue -ErrorAction Stop
    Write-Host "USB storage $action."
} catch {
    Write-Error "Failed to set USB storage state: $($_.Exception.Message)"
    exit 1
}
