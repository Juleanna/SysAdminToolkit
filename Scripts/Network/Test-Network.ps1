param(
    [string]$Target = '8.8.8.8'
)

Write-Host "Пінг $Target..." -ForegroundColor Cyan
try {
    Test-Connection -ComputerName $Target -Count 4 -ErrorAction Stop
} catch {
    Write-Warning "Пінг не вдався: $($_.Exception.Message)"
}

Write-Host "`nDNS перевірка..." -ForegroundColor Cyan
try {
    Resolve-DnsName 'google.com' -ErrorAction Stop | Format-Table -AutoSize
} catch {
    Write-Warning "DNS не працює: $($_.Exception.Message)"
}

Write-Host "`nПоточна IP конфігурація:" -ForegroundColor Cyan
try {
    Get-NetIPConfiguration -ErrorAction Stop | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway -AutoSize
} catch {
    Write-Warning "Не вдалося отримати конфігурацію: $($_.Exception.Message)"
}
