<#
.SYNOPSIS
    Створення та порівняння знімків конфігурації системи.
.DESCRIPTION
    Без -BaselinePath створює новий знімок. З -BaselinePath порівнює поточний стан зі знімком.
.PARAMETER BaselinePath
    Шлях до попереднього знімку JSON. Якщо не вказано — створюється новий.
.PARAMETER ExportHtml
    Зберегти результат порівняння у HTML.
.EXAMPLE
    .\Compare-Snapshot.ps1
    .\Compare-Snapshot.ps1 -BaselinePath "Reports\baseline_20260225.json"
#>
param(
    [string]$BaselinePath,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

function Get-SystemSnapshot {
    $snapshot = [ordered]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Computer  = $env:COMPUTERNAME
        Software  = @(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName | Sort-Object)
        Services  = @(Get-Service | Select-Object Name, Status, StartType | Sort-Object Name)
        Tasks     = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
            Select-Object TaskName, State | Sort-Object TaskName)
        Users     = @(Get-LocalUser | Select-Object Name, Enabled | Sort-Object Name)
        Firewall  = @(Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue | Measure-Object).Count
        Ports     = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
    }
    return $snapshot
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Знімок/Порівняння конфігурації" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$current = Get-SystemSnapshot

if (-not $BaselinePath) {
    $savePath = Join-Path (Get-ToolkitRoot) "Reports\baseline_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $current | ConvertTo-Json -Depth 5 | Set-Content -Path $savePath -Encoding UTF8
    Write-Host "Знімок збережено: $savePath" -ForegroundColor Green
    Write-Host "  ПЗ: $($current.Software.Count)" -ForegroundColor White
    Write-Host "  Сервіси: $($current.Services.Count)" -ForegroundColor White
    Write-Host "  Завдання: $($current.Tasks.Count)" -ForegroundColor White
    Write-Host "  Користувачі: $($current.Users.Count)" -ForegroundColor White
    Write-Host "  Правила FW: $($current.Firewall)" -ForegroundColor White
    Write-Host "  Відкриті порти: $($current.Ports.Count)" -ForegroundColor White
    Write-TkLog "Compare-Snapshot: створено знімок $savePath" -Level INFO
    exit 0
}

if (-not (Test-Path $BaselinePath)) {
    $fullPath = Join-Path (Get-ToolkitRoot) $BaselinePath
    if (Test-Path $fullPath) { $BaselinePath = $fullPath }
    else { Write-Host "Файл базового знімку не знайдено: $BaselinePath" -ForegroundColor Red; exit 1 }
}

$baseline = Get-Content $BaselinePath -Encoding UTF8 | ConvertFrom-Json
$diffs = [System.Collections.ArrayList]::new()

Write-Host "Базовий знімок: $($baseline.Timestamp)" -ForegroundColor Gray
Write-Host "Поточний:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ПЗ
$addedSw = $current.Software | Where-Object { $_ -notin $baseline.Software }
$removedSw = $baseline.Software | Where-Object { $_ -notin $current.Software }
if ($addedSw -or $removedSw) {
    Write-Host "--- Програмне забезпечення ---" -ForegroundColor Cyan
    $addedSw | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green; [void]$diffs.Add([PSCustomObject]@{ Категорія="ПЗ"; Зміна="Додано"; Елемент=$_ }) }
    $removedSw | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red; [void]$diffs.Add([PSCustomObject]@{ Категорія="ПЗ"; Зміна="Видалено"; Елемент=$_ }) }
}

# Сервіси
$curSvc = $current.Services | ForEach-Object { "$($_.Name)|$($_.Status)|$($_.StartType)" }
$baseSvc = $baseline.Services | ForEach-Object { "$($_.Name)|$($_.Status)|$($_.StartType)" }
$addedS = $curSvc | Where-Object { $_ -notin $baseSvc }
$removedS = $baseSvc | Where-Object { $_ -notin $curSvc }
if ($addedS -or $removedS) {
    Write-Host "--- Сервіси ---" -ForegroundColor Cyan
    $addedS | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green; [void]$diffs.Add([PSCustomObject]@{ Категорія="Сервіс"; Зміна="Змінено/Додано"; Елемент=$_ }) }
    $removedS | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red; [void]$diffs.Add([PSCustomObject]@{ Категорія="Сервіс"; Зміна="Змінено/Видалено"; Елемент=$_ }) }
}

# Порти
$addedP = $current.Ports | Where-Object { $_ -notin $baseline.Ports }
$removedP = $baseline.Ports | Where-Object { $_ -notin $current.Ports }
if ($addedP -or $removedP) {
    Write-Host "--- Відкриті порти ---" -ForegroundColor Cyan
    $addedP | ForEach-Object { Write-Host "  + Порт $_" -ForegroundColor Green; [void]$diffs.Add([PSCustomObject]@{ Категорія="Порт"; Зміна="Відкрито"; Елемент="$_" }) }
    $removedP | ForEach-Object { Write-Host "  - Порт $_" -ForegroundColor Red; [void]$diffs.Add([PSCustomObject]@{ Категорія="Порт"; Зміна="Закрито"; Елемент="$_" }) }
}

Write-Host "`nВсього змін: $($diffs.Count)" -ForegroundColor $(if($diffs.Count -gt 0){"Yellow"}else{"Green"})

if ($ExportHtml -and $diffs.Count -gt 0) {
    $path = Join-Path (Get-ToolkitRoot) "Reports\Snapshot-Diff_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    Export-TkReport -Data $diffs -Path $path -Title "Порівняння знімків" -Format HTML
    Write-Host "Звіт: $path" -ForegroundColor Green
}
Write-TkLog "Compare-Snapshot: $($diffs.Count) змін" -Level INFO
