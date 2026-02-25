$utf8Bom = New-Object System.Text.UTF8Encoding $true
$files = Get-ChildItem -Path $PSScriptRoot -Recurse -Include '*.ps1','*.psm1','*.psd1' |
    Where-Object { $_.FullName -notlike '*\.claude\*' -and $_.FullName -notlike '*\_apply_bom*' }

$fixed = 0
$already = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($f.FullName, $content, $utf8Bom)
        Write-Host "BOM+ $($f.FullName)" -ForegroundColor Green
        $fixed++
    } else {
        $already++
    }
}
Write-Host "Added BOM: $fixed, Already had: $already" -ForegroundColor Cyan
