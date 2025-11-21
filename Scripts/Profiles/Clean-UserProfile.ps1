$dirs = @(
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent"
)

foreach ($d in $dirs) {
    if (Test-Path $d) {
        Write-Host "Очищаю: $d"
        Remove-Item "$d\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
