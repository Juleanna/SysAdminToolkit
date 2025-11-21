param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)]
    [string]$ProcessName
)

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    param($ProcessName)
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
} -ArgumentList $ProcessName

Write-Host "Процесс $ProcessName завершён на $ComputerName"
