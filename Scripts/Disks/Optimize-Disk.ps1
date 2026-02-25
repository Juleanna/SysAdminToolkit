param(
    [string]$DriveLetter = "C",
    [ValidateSet('Analyze','Optimize','Retrim')]
    [string]$Mode = 'Analyze'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Оптимізація диска ${DriveLetter}:" -ForegroundColor Cyan
Write-Host "  Режим: $Mode" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Optimize-Disk: Старт, диск=$DriveLetter, режим=$Mode" -Level INFO

# --- Визначення типу диска ---
Write-Host "`n--- Визначення типу носія ---" -ForegroundColor Cyan
$mediaType = "Unknown"
try {
    $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
    $physDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $partition.DiskNumber } | Select-Object -First 1
    if ($physDisk) {
        $mediaType = $physDisk.MediaType
        Write-Host "  Диск: $($physDisk.FriendlyName)" -ForegroundColor Gray
        Write-Host "  Тип: $mediaType" -ForegroundColor $(if ($mediaType -eq 'SSD') { 'Green' } else { 'Gray' })
        Write-Host "  Розмір: $([math]::Round($physDisk.Size / 1GB, 1)) GB" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [УВАГА] Не вдалося визначити тип диска: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 15"

# --- Інформація про том ---
Write-Host "`n--- Стан тому ---" -ForegroundColor Cyan
try {
    $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    $freePct = if ($vol.Size -gt 0) { [math]::Round($vol.SizeRemaining / $vol.Size * 100, 1) } else { 0 }
    Write-Host "  Файлова система: $($vol.FileSystemType)" -ForegroundColor Gray
    Write-Host "  Вільно: $([math]::Round($vol.SizeRemaining / 1GB, 2)) GB ($freePct%)" -ForegroundColor Gray
} catch {
    Write-Host "  [УВАГА] Не вдалося отримати інформацію про том" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 25"

# --- Основна операція ---
switch ($Mode) {
    'Analyze' {
        Write-Host "`n--- Аналіз фрагментації ---" -ForegroundColor Cyan
        try {
            $result = Optimize-Volume -DriveLetter $DriveLetter -Analyze -Verbose 4>&1 2>&1
            foreach ($line in $result) {
                Write-Host "  $line" -ForegroundColor Gray
            }
            Write-Host "`n[OK] Аналіз завершено." -ForegroundColor Green
            Write-TkLog "Optimize-Disk: Аналіз завершено для ${DriveLetter}:" -Level INFO
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Optimize-Disk: Помилка аналізу: $($_.Exception.Message)" -Level ERROR
        }
    }
    'Optimize' {
        if ($mediaType -eq 'SSD') {
            Write-Host "`n--- TRIM для SSD ---" -ForegroundColor Cyan
            Write-Host "  Виконується TRIM-оптимізація..." -ForegroundColor Gray
            try {
                Optimize-Volume -DriveLetter $DriveLetter -ReTrim -ErrorAction Stop
                Write-Host "`n[OK] TRIM успішно виконано." -ForegroundColor Green
                Write-TkLog "Optimize-Disk: TRIM виконано для SSD ${DriveLetter}:" -Level INFO
            } catch {
                Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Optimize-Disk: Помилка TRIM: $($_.Exception.Message)" -Level ERROR
            }
        } else {
            Write-Host "`n--- Дефрагментація HDD ---" -ForegroundColor Cyan
            Write-Host "  Виконується дефрагментація (може зайняти тривалий час)..." -ForegroundColor Yellow
            try {
                Optimize-Volume -DriveLetter $DriveLetter -Defrag -ErrorAction Stop
                Write-Host "`n[OK] Дефрагментацію успішно завершено." -ForegroundColor Green
                Write-TkLog "Optimize-Disk: Дефрагментацію завершено для HDD ${DriveLetter}:" -Level INFO
            } catch {
                Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Optimize-Disk: Помилка дефрагментації: $($_.Exception.Message)" -Level ERROR
            }
        }
    }
    'Retrim' {
        Write-Host "`n--- Примусовий TRIM ---" -ForegroundColor Cyan
        if ($mediaType -ne 'SSD') {
            Write-Host "  [УВАГА] Диск не є SSD, але TRIM буде виконано за запитом." -ForegroundColor Yellow
        }
        try {
            Optimize-Volume -DriveLetter $DriveLetter -ReTrim -ErrorAction Stop
            Write-Host "`n[OK] TRIM успішно виконано." -ForegroundColor Green
            Write-TkLog "Optimize-Disk: ReTrim виконано для ${DriveLetter}:" -Level INFO
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Optimize-Disk: Помилка ReTrim: $($_.Exception.Message)" -Level ERROR
        }
    }
}
Write-Host "PROGRESS: 100"

Write-Host "`n[Завершено] Оптимізація диска ${DriveLetter}: ($Mode)" -ForegroundColor Cyan
