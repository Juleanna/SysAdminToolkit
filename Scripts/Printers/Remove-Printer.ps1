param(
    [string]$PrinterName="HP-LaserJet"
)

Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
Write-Host "Принтер удален: $PrinterName"
