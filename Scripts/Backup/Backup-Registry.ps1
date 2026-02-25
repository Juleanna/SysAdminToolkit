param(
    [string]$BackupPath,
    [string]$SpecificKey
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

$cfg = Get-ToolkitConfig
if (-not $BackupPath) { $BackupPath = Join-Path $cfg.DefaultBackupPath "Registry" }

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$destDir = Join-Path $BackupPath "Registry_$timestamp"

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Бекап реєстру Windows" -ForegroundColor Cyan
Write-Host "  Папка: $destDir" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Backup-Registry: Старт, шлях=$destDir" -Level INFO

$success = 0
$errors = 0

if ($SpecificKey) {
    # Експорт конкретного ключа
    $safeName = ($SpecificKey -replace '\\','_' -replace ':','') + ".reg"
    $outFile = Join-Path $destDir $safeName
    Write-Host "`n  Експорт: $SpecificKey" -ForegroundColor Gray
    try {
        $result = & reg export "$SpecificKey" "$outFile" /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            $size = [math]::Round((Get-Item $outFile).Length / 1KB, 1)
            Write-Host "  [OK] $safeName ($size KB)" -ForegroundColor Green
            $success++
        } else {
            Write-Host "  [ПОМИЛКА] $result" -ForegroundColor Red
            $errors++
        }
    } catch {
        Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
} else {
    # Експорт стандартних гілок
    $hives = @(
        @{ Name="HKLM_SOFTWARE"; Key="HKLM\SOFTWARE" }
        @{ Name="HKLM_SYSTEM";   Key="HKLM\SYSTEM" }
        @{ Name="HKLM_SAM";      Key="HKLM\SAM" }
        @{ Name="HKCU";           Key="HKCU" }
        @{ Name="HKLM_SECURITY";  Key="HKLM\SECURITY" }
    )

    $step = 0
    foreach ($hive in $hives) {
        $step++
        $pct = [math]::Round($step / $hives.Count * 90)
        Write-Host "PROGRESS: $pct"

        $outFile = Join-Path $destDir "$($hive.Name).reg"
        Write-Host "`n  Експорт: $($hive.Key)" -ForegroundColor Gray

        try {
            $result = & reg export "$($hive.Key)" "$outFile" /y 2>&1
            if ($LASTEXITCODE -eq 0) {
                $size = [math]::Round((Get-Item $outFile).Length / 1MB, 2)
                Write-Host "  [OK] $($hive.Name).reg ($size MB)" -ForegroundColor Green
                Write-TkLog "Експортовано: $($hive.Key) -> $($hive.Name).reg ($size MB)" -Level INFO
                $success++
            } else {
                Write-Host "  [УВАГА] $result" -ForegroundColor Yellow
                Write-TkLog "Увага при експорті $($hive.Key): $result" -Level WARN
                $errors++
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Помилка експорту $($hive.Key): $($_.Exception.Message)" -Level ERROR
            $errors++
        }
    }
}

Write-Host "PROGRESS: 100"

# --- Підсумок ---
$totalSize = 0
Get-ChildItem -Path $destDir -File -ErrorAction SilentlyContinue | ForEach-Object { $totalSize += $_.Length }
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Підсумок бекапу реєстру" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Експортовано: $success" -ForegroundColor Green
if ($errors -gt 0) { Write-Host "  Помилок: $errors" -ForegroundColor Red }
Write-Host "  Загальний розмір: $totalSizeMB MB" -ForegroundColor Gray
Write-Host "  Шлях: $destDir" -ForegroundColor Gray

Write-Host "`n[Завершено] Бекап реєстру" -ForegroundColor Cyan
Write-TkLog "Backup-Registry завершено: $success експортовано, $errors помилок, $totalSizeMB MB" -Level INFO
