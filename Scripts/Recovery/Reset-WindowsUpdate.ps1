param()

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Скидання компонентів Windows Update" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Reset-WindowsUpdate: Старт" -Level INFO

$success = 0
$errors = 0

# --- Крок 1: Зупинка сервісів ---
Write-Host "`n--- Крок 1/6: Зупинка сервісів ---" -ForegroundColor Cyan
$services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "  [OK] Зупинено: $svc" -ForegroundColor Green
        } else {
            Write-Host "  [--] $svc вже зупинено або не знайдено" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [УВАГА] Не вдалося зупинити $svc`: $($_.Exception.Message)" -ForegroundColor Yellow
        $errors++
    }
}
Write-Host "PROGRESS: 17"

# --- Крок 2: Перейменування SoftwareDistribution ---
Write-Host "`n--- Крок 2/6: Перейменування SoftwareDistribution ---" -ForegroundColor Cyan
$sdPath = Join-Path $env:WINDIR "SoftwareDistribution"
$sdBackup = "${sdPath}.old.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
if (Test-Path $sdPath) {
    try {
        Rename-Item -Path $sdPath -NewName (Split-Path $sdBackup -Leaf) -Force -ErrorAction Stop
        Write-Host "  [OK] Перейменовано -> $(Split-Path $sdBackup -Leaf)" -ForegroundColor Green
        Write-TkLog "SoftwareDistribution перейменовано" -Level INFO
        $success++
    } catch {
        Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка перейменування SoftwareDistribution: $($_.Exception.Message)" -Level ERROR
        $errors++
    }
} else {
    Write-Host "  [--] Папку не знайдено (вже перейменована?)" -ForegroundColor Gray
}
Write-Host "PROGRESS: 33"

# --- Крок 3: Перейменування catroot2 ---
Write-Host "`n--- Крок 3/6: Перейменування catroot2 ---" -ForegroundColor Cyan
$crPath = Join-Path $env:WINDIR "System32\catroot2"
$crBackup = "${crPath}.old.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
if (Test-Path $crPath) {
    try {
        Rename-Item -Path $crPath -NewName (Split-Path $crBackup -Leaf) -Force -ErrorAction Stop
        Write-Host "  [OK] Перейменовано -> $(Split-Path $crBackup -Leaf)" -ForegroundColor Green
        Write-TkLog "catroot2 перейменовано" -Level INFO
        $success++
    } catch {
        Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка перейменування catroot2: $($_.Exception.Message)" -Level ERROR
        $errors++
    }
} else {
    Write-Host "  [--] Папку не знайдено" -ForegroundColor Gray
}
Write-Host "PROGRESS: 50"

# --- Крок 4: Скидання Winsock ---
Write-Host "`n--- Крок 4/6: Скидання Winsock ---" -ForegroundColor Cyan
try {
    $out = & netsh winsock reset 2>&1
    Write-Host "  [OK] Winsock скинуто" -ForegroundColor Green
    $success++
} catch {
    Write-Host "  [УВАГА] $($_.Exception.Message)" -ForegroundColor Yellow
    $errors++
}
Write-Host "PROGRESS: 67"

# --- Крок 5: Запуск сервісів ---
Write-Host "`n--- Крок 5/6: Запуск сервісів ---" -ForegroundColor Cyan
foreach ($svc in $services) {
    try {
        Start-Service -Name $svc -ErrorAction Stop
        Write-Host "  [OK] Запущено: $svc" -ForegroundColor Green
    } catch {
        Write-Host "  [УВАГА] Не вдалося запустити $svc`: $($_.Exception.Message)" -ForegroundColor Yellow
        $errors++
    }
}
Write-Host "PROGRESS: 83"

# --- Крок 6: Ініціювання пошуку оновлень ---
Write-Host "`n--- Крок 6/6: Ініціювання пошуку оновлень ---" -ForegroundColor Cyan
try {
    $usoclient = Get-Command usoclient -ErrorAction SilentlyContinue
    if ($usoclient) {
        & usoclient StartScan 2>&1 | Out-Null
        Write-Host "  [OK] usoclient StartScan виконано" -ForegroundColor Green
    } else {
        & wuauclt /detectnow 2>&1 | Out-Null
        Write-Host "  [OK] wuauclt /detectnow виконано" -ForegroundColor Green
    }
    $success++
} catch {
    Write-Host "  [УВАГА] Не вдалося ініціювати сканування: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host "PROGRESS: 100"

# --- Підсумок ---
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Підсумок скидання Windows Update" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Успішних операцій: $success" -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "  Помилок: $errors" -ForegroundColor Red
    Write-Host "`n[УВАГА] Рекомендується перезавантажити комп'ютер." -ForegroundColor Yellow
} else {
    Write-Host "  Помилок: 0" -ForegroundColor Green
}
Write-Host "`n[Завершено] Скидання Windows Update" -ForegroundColor Cyan
Write-TkLog "Reset-WindowsUpdate завершено: успішно=$success, помилок=$errors" -Level $(if($errors -gt 0){'WARN'}else{'INFO'})
