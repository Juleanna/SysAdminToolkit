Write-Host "=== CPU ==="
Get-CimInstance Win32_Processor | Select-Object Name, LoadPercentage

Write-Host "`n=== RAM ==="
$os = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{
    TotalGB = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
    FreeGB  = [math]::Round($os.FreePhysicalMemory/1MB,2)
} | Format-List

Write-Host "`n=== DISKS ==="
Get-PSDrive -PSProvider FileSystem |
    Select-Object Name,@{n='FreeGB';e={[math]::Round($_.Free/1GB,2)}},@{n='UsedGB';e={[math]::Round(($_.Used)/1GB,2)}} |
    Format-Table -AutoSize

Write-Host "`n=== TOP PROCESSES (CPU) ==="
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,Id,CPU,WS |
    Format-Table -AutoSize
