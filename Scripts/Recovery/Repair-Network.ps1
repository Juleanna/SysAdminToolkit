$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора."
    exit 1
}

Write-Host "Скидання Winsock..." -ForegroundColor Cyan
$result = netsh winsock reset 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Помилка Winsock: $result"
} else {
    Write-Host "  OK" -ForegroundColor Green
}

Write-Host "Скидання IP..." -ForegroundColor Cyan
$result = netsh int ip reset 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Помилка IP reset: $result"
} else {
    Write-Host "  OK" -ForegroundColor Green
}

Write-Host "Очищення DNS-кешу..." -ForegroundColor Cyan
$result = ipconfig /flushdns 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Помилка DNS flush: $result"
} else {
    Write-Host "  OK" -ForegroundColor Green
}

Write-Host "`nМережу скинуто. Може знадобитися перезавантаження." -ForegroundColor Yellow
