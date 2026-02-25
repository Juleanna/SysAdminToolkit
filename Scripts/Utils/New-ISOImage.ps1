<#
.SYNOPSIS
    Створення ISO-образу з папки.
.DESCRIPTION
    Використовує IMAPI2 COM для генерації ISO-файлу з вмісту папки.
.PARAMETER SourcePath
    Шлях до вихідної папки.
.PARAMETER OutputPath
    Шлях до вихідного ISO-файлу.
.PARAMETER VolumeName
    Назва тому. За замовчуванням "SYSADMIN_TOOLKIT".
.EXAMPLE
    .\New-ISOImage.ps1 -SourcePath "D:\Deploy" -OutputPath "D:\deploy.iso"
#>
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$VolumeName = "SYSADMIN_TOOLKIT"
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

if (-not (Test-Path $SourcePath)) {
    Write-Host "Вихідна папка не знайдена: $SourcePath" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Створення ISO-образу" -ForegroundColor Cyan
Write-Host "  Джерело: $SourcePath" -ForegroundColor White
Write-Host "  Вихід:   $OutputPath" -ForegroundColor White
Write-Host "  Том:     $VolumeName" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.VolumeName = $VolumeName
    $fsi.FileSystemsToCreate = 4  # FsiFileSystemISO9660 + FsiFileSystemJoliet

    Write-Host "Додаю файли..." -ForegroundColor Gray
    $fsi.Root.AddTree($SourcePath, $false)

    Write-Host "Генерую образ..." -ForegroundColor Gray
    $result = $fsi.CreateResultImage()
    $stream = $result.ImageStream

    $outDir = Split-Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $fileStream = [System.IO.File]::Create($OutputPath)
    $buffer = New-Object byte[] 65536
    do {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -gt 0) { $fileStream.Write($buffer, 0, $read) }
    } while ($read -gt 0)

    $fileStream.Close()
    [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($stream) | Out-Null
    [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($fsi) | Out-Null

    $sizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
    Write-Host "ISO створено: $OutputPath ($sizeMB МБ)" -ForegroundColor Green
    Write-TkLog "New-ISOImage: $OutputPath ($sizeMB МБ)" -Level INFO
} catch {
    Write-Host "Помилка створення ISO: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "New-ISOImage помилка: $($_.Exception.Message)" -Level ERROR
}
