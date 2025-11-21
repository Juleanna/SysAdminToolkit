param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-Process | Select Name,Id,CPU,WS
}
