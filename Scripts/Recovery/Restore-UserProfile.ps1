<#
.SYNOPSIS
    Відновлення профілю користувача з бекапу.
.DESCRIPTION
    Копіює дані профілю з резервної копії. Без -Force показує що буде відновлено.
.PARAMETER BackupPath
    Шлях до бекапу профілю.
.PARAMETER Username
    Ім'я користувача для відновлення.
.PARAMETER Force
    Виконати відновлення.
.EXAMPLE
    .\Restore-UserProfile.ps1 -BackupPath "D:\Backups\jdoe" -Username "jdoe" -Force
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][string]$BackupPath,
    [Parameter(Mandatory=$true)][string]$Username,
    [switch]$Force
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

if (-not (Test-Path $BackupPath)) {
    Write-Host "Бекап не знайдено: $BackupPath" -ForegroundColor Red
    exit 1
}

$targetPath = "C:\Users\$Username"
$excludeFiles = @("ntuser.dat.LOG*", "UsrClass.dat*", "NTUSER.DAT", "ntuser.dat.LOG1", "ntuser.dat.LOG2", "ntuser.ini")

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Відновлення профілю: $Username" -ForegroundColor Cyan
Write-Host "  З бекапу: $BackupPath" -ForegroundColor White
Write-Host "  Ціль:     $targetPath" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem -Path $BackupPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $name = $_.Name; -not ($excludeFiles | Where-Object { $name -like $_ }) }

$totalSizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

Write-Host "Файлів для відновлення: $(@($files).Count)" -ForegroundColor White
Write-Host "Загальний розмір: $totalSizeMB МБ" -ForegroundColor White
Write-Host ""

if (-not $Force) {
    Write-Host "Для відновлення запустіть з параметром -Force" -ForegroundColor Yellow
    Write-Host "Приклад: .\Restore-UserProfile.ps1 -BackupPath '$BackupPath' -Username '$Username' -Force" -ForegroundColor Gray
    exit 0
}

if ($PSCmdlet.ShouldProcess($targetPath, "Відновити профіль з $BackupPath")) {
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    $restored = 0; $errors = 0
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($BackupPath.Length)
        $destPath = Join-Path $targetPath $relativePath
        $destDir = Split-Path $destPath -Parent
        try {
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction Stop
            $restored++
        } catch {
            $errors++
            Write-Host "  Помилка: $relativePath — $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`nВідновлено файлів: $restored" -ForegroundColor Green
    if ($errors -gt 0) { Write-Host "Помилок: $errors" -ForegroundColor Red }
    Write-TkLog "Restore-UserProfile: $Username — відновлено $restored, помилок $errors" -Level INFO
}
