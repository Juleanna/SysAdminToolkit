param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)]
    [string]$ProcessName
)

try {
    $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        param($ProcessName)
        $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $procs) { return "NOT_FOUND" }
        $procs | Stop-Process -Force
        return @($procs).Count
    } -ArgumentList $ProcessName -ErrorAction Stop

    if ($result -eq "NOT_FOUND") {
        Write-Warning "Процес $ProcessName не знайдено на $ComputerName."
    } else {
        Write-Host "Завершено $result процесів '$ProcessName' на $ComputerName." -ForegroundColor Green
    }
} catch {
    Write-Error "Не вдалося завершити процес: $($_.Exception.Message)"
    exit 1
}
