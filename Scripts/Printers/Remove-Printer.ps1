param(
    [Parameter(Mandatory=$true)]
    [string]$PrinterName
)

$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $printer) {
    Write-Error "Принтер не знайдено: $PrinterName"
    exit 1
}

try {
    Remove-Printer -Name $PrinterName -ErrorAction Stop
    Write-Host "Принтер видалено: $PrinterName" -ForegroundColor Green
} catch {
    Write-Error "Не вдалося видалити принтер: $($_.Exception.Message)"
    exit 1
}
