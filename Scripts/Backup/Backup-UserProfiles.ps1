. "$PSScriptRoot\..\Utils\ToolkitCommon.psm1"

param(
    [string]$DestRoot
)

$cfg = Get-ToolkitConfig
if (-not $DestRoot) {
    $DestRoot = Join-Path $cfg.DefaultBackupPath "UserProfiles"
}

$profiles = Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special }

foreach ($p in $profiles) {
    $path = $p.LocalPath
    if (-not (Test-Path $path)) { continue }

    $userName = Split-Path $path -Leaf
    $dest = Join-Path $DestRoot $userName

    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest | Out-Null
    }

    $date = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $target = Join-Path $dest $date

    Write-Host "Сохраняем профиль $userName -> $target"
    try {
        robocopy $path $target /MIR /R:1 /W:2 /NFL /NDL /NP /NJH /NJS | Out-Null
    } catch {
        Write-Warning "Ошибка при копировании профиля $userName: $($_.Exception.Message)"
    }
}
