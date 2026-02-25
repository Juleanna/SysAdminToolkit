[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$IncludeWinSxS
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Комплексне очищення системного сміття" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Clean-SystemJunk: Старт" -Level INFO

# Визначення цілей для очищення
$targets = @(
    @{ Name="Windows Temp";           Path="$env:WINDIR\Temp" }
    @{ Name="User Temp";              Path=$env:TEMP }
    @{ Name="Prefetch";               Path="$env:WINDIR\Prefetch" }
    @{ Name="Thumbnails";             Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Filter="thumbcache_*.db" }
    @{ Name="Error Reports (Local)";  Path="$env:LOCALAPPDATA\Microsoft\Windows\WER" }
    @{ Name="Error Reports (System)"; Path="$env:PROGRAMDATA\Microsoft\Windows\WER" }
    @{ Name="Memory Dumps";           Path="$env:WINDIR\Minidump" }
    @{ Name="Memory Dump (MEMORY.DMP)"; Path="$env:WINDIR"; Filter="MEMORY.DMP" }
    @{ Name="Font Cache";             Path="$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache" }
    @{ Name="Windows Update Cache";   Path="$env:WINDIR\SoftwareDistribution\Download" }
    @{ Name="Windows Logs (CBS)";     Path="$env:WINDIR\Logs\CBS"; Filter="*.log" }
    @{ Name="Installer Temp";         Path="$env:WINDIR\Temp\*.tmp" }
)

function Get-FolderSize {
    param([string]$Path, [string]$Filter)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        if ($Filter) {
            $items = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue
        } else {
            $items = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        }
        ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch { 0 }
}

$totalFreed = 0
$results = @()
$step = 0
$totalSteps = $targets.Count + 2  # +1 Recycle Bin, +1 WinSxS (optional)

foreach ($target in $targets) {
    $step++
    $pct = [math]::Round($step / $totalSteps * 90)
    Write-Host "PROGRESS: $pct"

    $path = $target.Path
    $filter = $target.Filter
    $name = $target.Name

    if (-not (Test-Path $path)) {
        Write-Host "  [--] $name — не знайдено" -ForegroundColor Gray
        $results += [PSCustomObject]@{ Target=$name; SizeMB="0"; Status="Не знайдено" }
        continue
    }

    $sizeBefore = Get-FolderSize -Path $path -Filter $filter
    $sizeMB = [math]::Round($sizeBefore / 1MB, 2)

    if ($sizeBefore -eq 0) {
        Write-Host "  [--] $name — порожньо (0 MB)" -ForegroundColor Gray
        $results += [PSCustomObject]@{ Target=$name; SizeMB="0"; Status="Порожньо" }
        continue
    }

    if ($PSCmdlet.ShouldProcess($name, "Видалити $sizeMB MB")) {
        try {
            if ($filter) {
                Get-ChildItem -Path $path -Filter $filter -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } else {
                Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
            $sizeAfter = Get-FolderSize -Path $path -Filter $filter
            $freed = $sizeBefore - $sizeAfter
            $freedMB = [math]::Round($freed / 1MB, 2)
            $totalFreed += $freed
            Write-Host "  [OK] $name — звільнено $freedMB MB" -ForegroundColor Green
            $results += [PSCustomObject]@{ Target=$name; SizeMB=$freedMB; Status="Очищено" }
        } catch {
            Write-Host "  [УВАГА] $name — частково очищено: $($_.Exception.Message)" -ForegroundColor Yellow
            $results += [PSCustomObject]@{ Target=$name; SizeMB=$sizeMB; Status="Частково" }
        }
    } else {
        Write-Host "  [WhatIf] $name — $sizeMB MB (було б видалено)" -ForegroundColor Yellow
        $results += [PSCustomObject]@{ Target=$name; SizeMB=$sizeMB; Status="WhatIf" }
        $totalFreed += $sizeBefore
    }
}

# --- Кошик ---
$step++
Write-Host "PROGRESS: $([math]::Round($step / $totalSteps * 90))"
if ($PSCmdlet.ShouldProcess("Кошик", "Очистити")) {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "  [OK] Кошик — очищено" -ForegroundColor Green
        $results += [PSCustomObject]@{ Target="Кошик"; SizeMB="?"; Status="Очищено" }
    } catch {
        Write-Host "  [УВАГА] Кошик — $($_.Exception.Message)" -ForegroundColor Yellow
        $results += [PSCustomObject]@{ Target="Кошик"; SizeMB="?"; Status="Помилка" }
    }
} else {
    Write-Host "  [WhatIf] Кошик — було б очищено" -ForegroundColor Yellow
    $results += [PSCustomObject]@{ Target="Кошик"; SizeMB="?"; Status="WhatIf" }
}

# --- WinSxS (опціонально) ---
if ($IncludeWinSxS) {
    $step++
    Write-Host "PROGRESS: $([math]::Round($step / $totalSteps * 90))"
    Write-Host "`n--- Очищення WinSxS (може зайняти 5-15 хвилин) ---" -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess("WinSxS Component Cleanup", "DISM /StartComponentCleanup")) {
        try {
            $tmpFile = New-TemporaryFile
            $proc = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -RedirectStandardOutput $tmpFile.FullName -NoNewWindow -PassThru -Wait
            $output = Get-Content $tmpFile.FullName -ErrorAction SilentlyContinue
            foreach ($line in $output) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Host "  $line" -ForegroundColor Gray
                }
            }
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0) {
                Write-Host "  [OK] WinSxS очищено" -ForegroundColor Green
                $results += [PSCustomObject]@{ Target="WinSxS Cleanup"; SizeMB="?"; Status="Очищено" }
            } else {
                Write-Host "  [УВАГА] DISM завершено з кодом $($proc.ExitCode)" -ForegroundColor Yellow
                $results += [PSCustomObject]@{ Target="WinSxS Cleanup"; SizeMB="?"; Status="Код: $($proc.ExitCode)" }
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            $results += [PSCustomObject]@{ Target="WinSxS Cleanup"; SizeMB="?"; Status="Помилка" }
        }
    } else {
        Write-Host "  [WhatIf] WinSxS — було б очищено" -ForegroundColor Yellow
    }
}

Write-Host "PROGRESS: 100"

# --- Підсумок ---
$totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
$totalFreedGB = [math]::Round($totalFreed / 1GB, 2)

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Результати очищення" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

if ($WhatIfPreference) {
    Write-Host "  Було б звільнено: ~$totalFreedMB MB ($totalFreedGB GB)" -ForegroundColor Yellow
} else {
    Write-Host "  Звільнено: ~$totalFreedMB MB ($totalFreedGB GB)" -ForegroundColor Green
}

Write-Host "`n[Завершено] Комплексне очищення системного сміття" -ForegroundColor Cyan
Write-TkLog "Clean-SystemJunk завершено: звільнено ~${totalFreedMB} MB" -Level INFO
