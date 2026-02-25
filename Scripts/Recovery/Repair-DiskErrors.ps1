param(
    [string]$DriveLetter = "C",
    [ValidateSet('Check','Fix','Full')]
    [string]$Mode = 'Check'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

# Прибираємо двокрапку якщо вказана
$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Перевірка та ремонт диска $DriveLetter`:" -ForegroundColor Cyan
Write-Host "  Режим: $Mode" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Repair-DiskErrors: Старт, диск=$DriveLetter, режим=$Mode" -Level INFO

# --- Фаза 1: SMART-статус ---
Write-Host "`n--- SMART-статус фізичних дисків ---" -ForegroundColor Cyan
try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop
    foreach ($pd in $physDisks) {
        $color = switch ($pd.HealthStatus) {
            'Healthy'  { 'Green' }
            'Warning'  { 'Yellow' }
            default    { 'Red' }
        }
        Write-Host "  $($pd.FriendlyName) | $($pd.MediaType) | $([math]::Round($pd.Size / 1GB, 1)) GB | Статус: $($pd.HealthStatus)" -ForegroundColor $color
    }
} catch {
    Write-Host "  [УВАГА] Не вдалося отримати SMART-дані: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 10"

# --- Фаза 2: Dirty bit ---
Write-Host "`n--- Перевірка dirty bit ---" -ForegroundColor Cyan
try {
    $dirty = & fsutil dirty query "${DriveLetter}:" 2>&1
    Write-Host "  $dirty" -ForegroundColor Gray
} catch {
    Write-Host "  [УВАГА] Не вдалося перевірити dirty bit" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 20"

# --- Фаза 3: Інформація про том ---
Write-Host "`n--- Інформація про том ${DriveLetter}: ---" -ForegroundColor Cyan
try {
    $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    $usedPct = if ($vol.Size -gt 0) { [math]::Round(($vol.Size - $vol.SizeRemaining) / $vol.Size * 100, 1) } else { 0 }
    Write-Host "  Файлова система: $($vol.FileSystemType)" -ForegroundColor Gray
    Write-Host "  Розмір: $([math]::Round($vol.Size / 1GB, 2)) GB" -ForegroundColor Gray
    Write-Host "  Вільно: $([math]::Round($vol.SizeRemaining / 1GB, 2)) GB ($usedPct% зайнято)" -ForegroundColor Gray
    Write-Host "  Стан: $($vol.HealthStatus)" -ForegroundColor $(if ($vol.HealthStatus -eq 'Healthy') { 'Green' } else { 'Red' })
} catch {
    Write-Host "  [УВАГА] Не вдалося отримати інформацію про том" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 30"

# --- Фаза 4: chkdsk ---
Write-Host "`n--- Запуск chkdsk (режим: $Mode) ---" -ForegroundColor Cyan

$chkdskArgs = "${DriveLetter}:"
switch ($Mode) {
    'Check' { $chkdskArgs = "${DriveLetter}:" }
    'Fix'   { $chkdskArgs = "${DriveLetter}: /f" }
    'Full'  { $chkdskArgs = "${DriveLetter}: /r" }
}

# Перевірка чи це системний диск і режим з виправленням
$systemDrive = $env:SystemDrive.TrimEnd(':').ToUpper()
if ($DriveLetter -eq $systemDrive -and $Mode -ne 'Check') {
    Write-Host "  [УВАГА] Диск ${DriveLetter}: є системним. Виправлення буде заплановано при наступному перезавантаженні." -ForegroundColor Yellow
    Write-TkLog "Системний диск — chkdsk буде заплановано на ребут" -Level WARN
}

$tmpFile = New-TemporaryFile
Write-Host "  Виконую: chkdsk $chkdskArgs ..." -ForegroundColor Gray
Write-TkLog "Запуск: chkdsk $chkdskArgs" -Level INFO

try {
    $proc = Start-Process -FilePath "chkdsk.exe" -ArgumentList $chkdskArgs -RedirectStandardOutput $tmpFile.FullName -NoNewWindow -PassThru -Wait -ErrorAction Stop

    $percent = 30
    while (-not $proc.HasExited) {
        $percent = [math]::Min(90, $percent + 2)
        Write-Host "PROGRESS: $percent"
        Start-Sleep -Seconds 3
    }

    Write-Host "PROGRESS: 95"

    # Вивід результатів
    $output = Get-Content $tmpFile.FullName -ErrorAction SilentlyContinue
    if ($output) {
        Write-Host "`n--- Результат chkdsk ---" -ForegroundColor Cyan
        foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '(error|помилк|bad|corrupt)') {
                Write-Host "  $line" -ForegroundColor Red
            } elseif ($line -match '(clean|no problems|is not dirty|без помилок)') {
                Write-Host "  $line" -ForegroundColor Green
            } else {
                Write-Host "  $line" -ForegroundColor Gray
            }
        }
    }

    # Аналіз exit code
    switch ($proc.ExitCode) {
        0 { Write-Host "`n[OK] Помилок не знайдено." -ForegroundColor Green; Write-TkLog "chkdsk завершено успішно, помилок немає" -Level INFO }
        1 { Write-Host "`n[OK] Помилки знайдено та виправлено." -ForegroundColor Green; Write-TkLog "chkdsk: помилки виправлено" -Level INFO }
        2 { Write-Host "`n[УВАГА] Потрібне перезавантаження для завершення перевірки." -ForegroundColor Yellow; Write-TkLog "chkdsk: потрібен ребут" -Level WARN }
        3 { Write-Host "`n[ПОМИЛКА] Не вдалося перевірити диск." -ForegroundColor Red; Write-TkLog "chkdsk: не вдалося перевірити" -Level ERROR }
        default { Write-Host "`n[УВАГА] chkdsk завершено з кодом: $($proc.ExitCode)" -ForegroundColor Yellow; Write-TkLog "chkdsk: код виходу $($proc.ExitCode)" -Level WARN }
    }
} catch {
    Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "chkdsk помилка: $($_.Exception.Message)" -Level ERROR
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}

Write-Host "PROGRESS: 100"
Write-Host "`n[Завершено] Перевірка диска ${DriveLetter}: ($Mode)" -ForegroundColor Cyan
