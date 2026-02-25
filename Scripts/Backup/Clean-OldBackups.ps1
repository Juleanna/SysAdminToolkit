[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$BackupPath,
    [int]$RetentionDays
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cfg = Get-ToolkitConfig
if (-not $BackupPath) { $BackupPath = $cfg.DefaultBackupPath }
if (-not $RetentionDays -or $RetentionDays -le 0) { $RetentionDays = $cfg.BackupRetentionDays }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Очищення старих резервних копій" -ForegroundColor Cyan
Write-Host "  Шлях: $BackupPath" -ForegroundColor Cyan
Write-Host "  Ретеншн: $RetentionDays днів" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Clean-OldBackups: Старт, шлях=$BackupPath, ретеншн=$RetentionDays днів" -Level INFO

if (-not (Test-Path $BackupPath)) {
    Write-Host "[ПОМИЛКА] Шлях не знайдено: $BackupPath" -ForegroundColor Red
    Write-TkLog "Clean-OldBackups: шлях не знайдено: $BackupPath" -Level ERROR
    exit 1
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
$allDirs = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue
$oldDirs = @($allDirs | Where-Object { $_.LastWriteTime -lt $cutoff })

Write-Host "`n  Всього папок: $($allDirs.Count)" -ForegroundColor Gray
Write-Host "  Старших за $RetentionDays днів: $($oldDirs.Count)" -ForegroundColor $(if ($oldDirs.Count -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "PROGRESS: 20"

if ($oldDirs.Count -eq 0) {
    Write-Host "`n[OK] Немає бекапів для видалення." -ForegroundColor Green
    Write-Host "PROGRESS: 100"
    Write-Host "`n[Завершено] Очищення бекапів" -ForegroundColor Cyan
    exit 0
}

$deleted = 0
$freedBytes = 0
$errors = 0
$results = @()
$step = 0

foreach ($dir in $oldDirs) {
    $step++
    $pct = 20 + [math]::Round($step / $oldDirs.Count * 70)
    Write-Host "PROGRESS: $pct"

    $age = [math]::Round(((Get-Date) - $dir.LastWriteTime).TotalDays, 0)
    $size = 0
    try { $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    $sizeMB = [math]::Round($size / 1MB, 2)

    if ($PSCmdlet.ShouldProcess($dir.Name, "Видалити ($sizeMB MB, $age днів)")) {
        try {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] $($dir.Name) — $sizeMB MB, $age днів" -ForegroundColor Green
            $deleted++
            $freedBytes += $size
            $results += [PSCustomObject]@{ Name=$dir.Name; SizeMB=$sizeMB; Age="$age дн."; Status="Видалено" }
        } catch {
            Write-Host "  [ПОМИЛКА] $($dir.Name) — $($_.Exception.Message)" -ForegroundColor Red
            $errors++
            $results += [PSCustomObject]@{ Name=$dir.Name; SizeMB=$sizeMB; Age="$age дн."; Status="Помилка" }
        }
    } else {
        Write-Host "  [WhatIf] $($dir.Name) — $sizeMB MB, $age днів" -ForegroundColor Yellow
        $freedBytes += $size
        $results += [PSCustomObject]@{ Name=$dir.Name; SizeMB=$sizeMB; Age="$age дн."; Status="WhatIf" }
    }
}

Write-Host "PROGRESS: 100"

# --- Підсумок ---
$freedMB = [math]::Round($freedBytes / 1MB, 2)
$freedGB = [math]::Round($freedBytes / 1GB, 2)

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Результати очищення бекапів" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
}

if ($WhatIfPreference) {
    Write-Host "  Було б звільнено: $freedMB MB ($freedGB GB)" -ForegroundColor Yellow
} else {
    Write-Host "  Видалено: $deleted папок" -ForegroundColor Green
    if ($errors -gt 0) { Write-Host "  Помилок: $errors" -ForegroundColor Red }
    Write-Host "  Звільнено: $freedMB MB ($freedGB GB)" -ForegroundColor Green
}

Write-Host "`n[Завершено] Очищення старих бекапів" -ForegroundColor Cyan
Write-TkLog "Clean-OldBackups завершено: видалено=$deleted, помилок=$errors, звільнено=${freedMB}MB" -Level INFO
