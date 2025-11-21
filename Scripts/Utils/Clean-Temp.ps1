$paths = @(
    $env:TEMP,
    "$env:WINDIR\Temp"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "Cleaning $p..."
        Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}
Write-Host "Temp folders cleaned."
