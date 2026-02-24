param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [string]$Message = "Повідомлення від адміністратора: зверніться до служби підтримки."
)

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($Message)
        msg * $Message
    } -ArgumentList $Message -ErrorAction Stop

    Write-Host "Повідомлення надіслано користувачу на $ComputerName." -ForegroundColor Green
} catch {
    Write-Error "Не вдалося надіслати повідомлення: $($_.Exception.Message)"
    exit 1
}
