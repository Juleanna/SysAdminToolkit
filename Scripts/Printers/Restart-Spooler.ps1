$svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Error "Службу Spooler не знайдено."
    exit 1
}

try {
    Restart-Service -Name Spooler -ErrorAction Stop
    Write-Host "Службу друку (Spooler) перезапущено." -ForegroundColor Green
} catch {
    Write-Error "Не вдалося перезапустити Spooler: $($_.Exception.Message)"
    exit 1
}
