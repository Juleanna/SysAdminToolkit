param(
    [string]$PrinterPath="\\server\HP-LaserJet"
)

rundll32 printui.dll,PrintUIEntry /in /n $PrinterPath
Write-Host "Принтер подключен: $PrinterPath"
