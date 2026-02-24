Write-Host "=== CPU ===" -ForegroundColor Cyan
try {
    Get-CimInstance Win32_Processor | Select-Object Name, LoadPercentage | Format-Table -AutoSize
} catch {
    Write-Warning "Не вдалося отримати дані CPU: $($_.Exception.Message)"
}

Write-Host "=== RAM ===" -ForegroundColor Cyan
try {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        TotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        FreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        UsedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
    } | Format-List
} catch {
    Write-Warning "Не вдалося отримати дані RAM: $($_.Exception.Message)"
}

Write-Host "=== ДИСКИ ===" -ForegroundColor Cyan
try {
    Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Used -or $_.Free } |
        Select-Object Name,
            @{n='FreeGB';e={[math]::Round($_.Free/1GB,2)}},
            @{n='UsedGB';e={[math]::Round($_.Used/1GB,2)}} |
        Format-Table -AutoSize
} catch {
    Write-Warning "Не вдалося отримати дані дисків: $($_.Exception.Message)"
}

Write-Host "=== TOP 10 ПРОЦЕСІВ (CPU) ===" -ForegroundColor Cyan
try {
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU,
        @{n='WS_MB';e={[math]::Round($_.WS/1MB,1)}} |
        Format-Table -AutoSize
} catch {
    Write-Warning "Не вдалося отримати процеси: $($_.Exception.Message)"
}
