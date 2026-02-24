param(
    [Parameter(Mandatory=$true)]
    [string]$PrinterPath
)

try {
    Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
    Write-Host "Принтер підключено: $PrinterPath" -ForegroundColor Green
} catch {
    Write-Error "Не вдалося додати принтер: $($_.Exception.Message)"
    exit 1
}
