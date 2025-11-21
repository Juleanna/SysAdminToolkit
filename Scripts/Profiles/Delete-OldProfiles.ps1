$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and
    $_.LocalPath -notlike "*$env:USERNAME*"
}

foreach ($p in $profiles) {
    Write-Host "Удаляю профиль: $($p.LocalPath)"
    Remove-CimInstance $p -ErrorAction SilentlyContinue
}
