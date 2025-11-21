param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [string]$Message = "Сообщение от администратора: свяжитесь со службой поддержки."
)

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    param($Message)
    msg * $Message
} -ArgumentList $Message

Write-Host "Сообщение отправлено пользователю на $ComputerName."
