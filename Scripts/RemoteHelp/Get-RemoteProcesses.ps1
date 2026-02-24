param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-Process | Select-Object Name, Id, CPU,
            @{n='WS_MB';e={[math]::Round($_.WS/1MB,1)}} |
            Sort-Object CPU -Descending
    } -ErrorAction Stop
} catch {
    Write-Error "Не вдалося отримати процеси з ${ComputerName}: $($_.Exception.Message)"
    exit 1
}
