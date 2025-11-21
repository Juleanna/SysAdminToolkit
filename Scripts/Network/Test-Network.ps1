param(
    [string]$Target = '8.8.8.8'
)

Write-Host "Pinging $Target..."
Test-Connection -ComputerName $Target -Count 4

Write-Host "`nDNS check..."
Resolve-DnsName 'google.com' -ErrorAction SilentlyContinue

Write-Host "`nCurrent IP configuration:"
Get-NetIPConfiguration | Format-Table
