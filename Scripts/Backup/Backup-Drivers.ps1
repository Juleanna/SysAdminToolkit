param(
    [string]$BackupPath
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

$cfg = Get-ToolkitConfig
if (-not $BackupPath) { $BackupPath = Join-Path $cfg.DefaultBackupPath "Drivers" }

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$destDir = Join-Path $BackupPath "Drivers_$timestamp"

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Бекап сторонніх драйверів" -ForegroundColor Cyan
Write-Host "  Папка: $destDir" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Backup-Drivers: Старт, шлях=$destDir" -Level INFO

Write-Host "PROGRESS: 10"

# --- Експорт драйверів через DISM ---
Write-Host "`n--- Експорт драйверів ---" -ForegroundColor Cyan
Write-Host "  Виконую DISM /Export-Driver (може зайняти кілька хвилин)..." -ForegroundColor Gray

$tmpFile = New-TemporaryFile
try {
    $proc = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Export-Driver /Destination:`"$destDir`"" `
        -RedirectStandardOutput $tmpFile.FullName -NoNewWindow -PassThru -Wait -ErrorAction Stop

    Write-Host "PROGRESS: 70"

    $output = Get-Content $tmpFile.FullName -ErrorAction SilentlyContinue
    $exported = 0
    foreach ($line in $output) {
        if ($line -match 'Exporting|export' -and $line -match '\.inf') {
            $exported++
        }
    }

    if ($proc.ExitCode -eq 0) {
        Write-Host "  [OK] DISM завершено успішно" -ForegroundColor Green
    } else {
        Write-Host "  [УВАГА] DISM завершено з кодом: $($proc.ExitCode)" -ForegroundColor Yellow
        Write-TkLog "DISM Export-Driver: код $($proc.ExitCode)" -Level WARN
    }
} catch {
    Write-Host "  [ПОМИЛКА] DISM не вдалося: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Спроба через pnputil..." -ForegroundColor Yellow

    try {
        $pnpResult = & pnputil /export-driver * "$destDir" 2>&1
        Write-Host "  [OK] pnputil завершено" -ForegroundColor Green
    } catch {
        Write-Host "  [ПОМИЛКА] pnputil також не вдалося: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Backup-Drivers: обидва методи невдалі" -Level ERROR
    }
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}

Write-Host "PROGRESS: 85"

# --- Підсумок: список драйверів ---
Write-Host "`n--- Експортовані драйвери ---" -ForegroundColor Cyan
$infFiles = Get-ChildItem -Path $destDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
$driverList = @()

foreach ($inf in $infFiles) {
    $provider = ""
    $class = ""
    try {
        $content = Get-Content $inf.FullName -TotalCount 50 -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match '^\s*Provider\s*=\s*["%]*([^"%]+)') { $provider = $Matches[1].Trim() }
            if ($line -match '^\s*Class\s*=\s*(.+)$') { $class = $Matches[1].Trim() }
        }
    } catch {}
    $driverList += [PSCustomObject]@{
        INF      = $inf.Name
        Provider = if ($provider) { $provider } else { "N/A" }
        Class    = if ($class) { $class } else { "N/A" }
    }
}

if ($driverList.Count -gt 0) {
    $driverList | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
}

Write-Host "PROGRESS: 100"

# --- Загальний підсумок ---
$totalSize = 0
Get-ChildItem -Path $destDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $totalSize += $_.Length }
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Підсумок бекапу драйверів" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Драйверів: $($infFiles.Count)" -ForegroundColor Green
Write-Host "  Розмір: $totalSizeMB MB" -ForegroundColor Gray
Write-Host "  Шлях: $destDir" -ForegroundColor Gray

Write-Host "`n[Завершено] Бекап драйверів" -ForegroundColor Cyan
Write-TkLog "Backup-Drivers завершено: $($infFiles.Count) драйверів, $totalSizeMB MB" -Level INFO
