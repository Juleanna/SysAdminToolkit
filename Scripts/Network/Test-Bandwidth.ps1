<#
.SYNOPSIS
    Вимірює пропускну здатність мережі до віддаленого комп'ютера.
.DESCRIPTION
    Створює тимчасовий файл заданого розміру, копіює його на віддалений
    комп'ютер через адміністративну шару (\\ComputerName\C$\Temp),
    вимірює час передачі та обчислює швидкість у МБ/с.
    Після завершення видаляє тимчасові файли на обох сторонах.
.PARAMETER ComputerName
    Ім'я або IP-адреса віддаленого комп'ютера.
    Обов'язковий параметр.
.PARAMETER SizeMB
    Розмір тестового файлу в мегабайтах. За замовчуванням: 10 МБ.
.EXAMPLE
    .\Test-Bandwidth.ps1 -ComputerName SRV-DC01
    Тестує пропускну здатність до SRV-DC01 файлом 10 МБ.
.EXAMPLE
    .\Test-Bandwidth.ps1 -ComputerName 192.168.1.10 -SizeMB 50
    Тестує пропускну здатність до 192.168.1.10 файлом 50 МБ.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [int]$SizeMB = 10
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск Test-Bandwidth до '$ComputerName' (SizeMB=$SizeMB)" -Level INFO

$localTempFile  = $null
$remoteTempFile = $null

try {
    # --- Перевірка доступності ---
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "         ТЕСТ ПРОПУСКНОЇ ЗДАТНОСТI МЕРЕЖI" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Ціль:           $ComputerName" -ForegroundColor Cyan
    Write-Host "Розмір файлу:   $SizeMB МБ" -ForegroundColor Cyan
    Write-Host "=====================================================`n" -ForegroundColor Cyan

    Write-Host "Перевірка доступності $ComputerName..." -ForegroundColor Yellow
    if (-not (Test-ComputerOnline -ComputerName $ComputerName)) {
        Write-Host "Комп'ютер '$ComputerName' недоступний." -ForegroundColor Red
        Write-TkLog "Test-Bandwidth: $ComputerName недоступний" -Level ERROR
        exit 1
    }
    Write-Host "Комп'ютер доступний." -ForegroundColor Green

    # --- Перевірка шари ---
    $remoteDir = "\\$ComputerName\C`$\Temp"
    Write-Host "Перевірка доступу до $remoteDir..." -ForegroundColor Yellow

    if (-not (Test-Path $remoteDir)) {
        try {
            New-Item -ItemType Directory -Path $remoteDir -Force | Out-Null
            Write-Host "Створено віддалену папку $remoteDir" -ForegroundColor Yellow
        } catch {
            Write-Host "Немає доступу до $remoteDir : $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Немає доступу до шари: $($_.Exception.Message)" -Level ERROR
            exit 1
        }
    }
    Write-Host "Доступ до шари підтверджено." -ForegroundColor Green

    # --- Створення тимчасового файлу ---
    Write-Host "`nСтворення тестового файлу ($SizeMB МБ)..." -ForegroundColor Yellow
    $localTempFile = Join-Path $env:TEMP ("BandwidthTest_{0}.dat" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    try {
        $fs = [System.IO.FileStream]::new($localTempFile, [System.IO.FileMode]::Create)
        $totalBytes = $SizeMB * 1MB
        $chunkSize = 1MB
        $buffer = [byte[]]::new($chunkSize)
        $random = [System.Random]::new()
        $written = 0

        while ($written -lt $totalBytes) {
            $random.NextBytes($buffer)
            $remaining = $totalBytes - $written
            $toWrite = [math]::Min($chunkSize, $remaining)
            $fs.Write($buffer, 0, $toWrite)
            $written += $toWrite
        }
        $fs.Close()
        $fs.Dispose()

        $actualSizeMB = [math]::Round((Get-Item $localTempFile).Length / 1MB, 2)
        Write-Host "Тестовий файл створено: $actualSizeMB МБ" -ForegroundColor Green
    } catch {
        Write-Host "Помилка створення тестового файлу: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка створення файлу: $($_.Exception.Message)" -Level ERROR
        exit 1
    }

    $remoteTempFile = Join-Path $remoteDir (Split-Path $localTempFile -Leaf)

    # --- Тест UPLOAD (локальний -> віддалений) ---
    Write-Host "`n--- UPLOAD: Локальний -> Віддалений ---" -ForegroundColor Yellow
    try {
        $uploadStart = [System.Diagnostics.Stopwatch]::StartNew()
        Copy-Item -Path $localTempFile -Destination $remoteTempFile -Force -ErrorAction Stop
        $uploadStart.Stop()

        $uploadSec = $uploadStart.Elapsed.TotalSeconds
        $uploadSpeed = if ($uploadSec -gt 0) { [math]::Round($actualSizeMB / $uploadSec, 2) } else { 0 }

        $uploadColor = if ($uploadSpeed -ge 50) { 'Green' } elseif ($uploadSpeed -ge 10) { 'Yellow' } else { 'Red' }

        Write-Host "Час передачі:    $([math]::Round($uploadSec, 3)) сек" -ForegroundColor Cyan
        Write-Host "Швидкість:       $uploadSpeed МБ/с" -ForegroundColor $uploadColor
    } catch {
        Write-Host "Помилка upload: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Upload error: $($_.Exception.Message)" -Level ERROR
        $uploadSpeed = 0
        $uploadSec = 0
    }

    # --- Тест DOWNLOAD (віддалений -> локальний) ---
    Write-Host "`n--- DOWNLOAD: Віддалений -> Локальний ---" -ForegroundColor Yellow
    $downloadTempFile = Join-Path $env:TEMP ("BandwidthTest_down_{0}.dat" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        $downloadStart = [System.Diagnostics.Stopwatch]::StartNew()
        Copy-Item -Path $remoteTempFile -Destination $downloadTempFile -Force -ErrorAction Stop
        $downloadStart.Stop()

        $downloadSec = $downloadStart.Elapsed.TotalSeconds
        $downloadSpeed = if ($downloadSec -gt 0) { [math]::Round($actualSizeMB / $downloadSec, 2) } else { 0 }

        $downloadColor = if ($downloadSpeed -ge 50) { 'Green' } elseif ($downloadSpeed -ge 10) { 'Yellow' } else { 'Red' }

        Write-Host "Час передачі:    $([math]::Round($downloadSec, 3)) сек" -ForegroundColor Cyan
        Write-Host "Швидкість:       $downloadSpeed МБ/с" -ForegroundColor $downloadColor
    } catch {
        Write-Host "Помилка download: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Download error: $($_.Exception.Message)" -Level ERROR
        $downloadSpeed = 0
        $downloadSec = 0
    }

    # --- Підсумок ---
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                     ПIДСУМОК" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Ціль:             $ComputerName" -ForegroundColor White
    Write-Host "Розмір файлу:     $actualSizeMB МБ" -ForegroundColor White

    if ($uploadSpeed -gt 0) {
        Write-Host "Upload:           $uploadSpeed МБ/с ($([math]::Round($uploadSec, 3)) сек)" -ForegroundColor $(if ($uploadSpeed -ge 50) { 'Green' } elseif ($uploadSpeed -ge 10) { 'Yellow' } else { 'Red' })
    }
    if ($downloadSpeed -gt 0) {
        Write-Host "Download:         $downloadSpeed МБ/с ($([math]::Round($downloadSec, 3)) сек)" -ForegroundColor $(if ($downloadSpeed -ge 50) { 'Green' } elseif ($downloadSpeed -ge 10) { 'Yellow' } else { 'Red' })
    }
    if ($uploadSpeed -gt 0 -and $downloadSpeed -gt 0) {
        $avgSpeed = [math]::Round(($uploadSpeed + $downloadSpeed) / 2, 2)
        Write-Host "Середня:          $avgSpeed МБ/с" -ForegroundColor Cyan
    }

    Write-TkLog "Test-Bandwidth до '$ComputerName': Upload=$uploadSpeed МБ/с, Download=$downloadSpeed МБ/с" -Level INFO

} catch {
    $errMsg = "Критична помилка Test-Bandwidth: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1

} finally {
    # --- Очистка тимчасових файлів ---
    Write-Host "`nОчистка тимчасових файлів..." -ForegroundColor DarkGray
    if ($localTempFile -and (Test-Path $localTempFile)) {
        Remove-Item $localTempFile -Force -ErrorAction SilentlyContinue
    }
    if ($remoteTempFile -and (Test-Path $remoteTempFile)) {
        Remove-Item $remoteTempFile -Force -ErrorAction SilentlyContinue
    }
    if ($downloadTempFile -and (Test-Path $downloadTempFile)) {
        Remove-Item $downloadTempFile -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Очистку завершено." -ForegroundColor DarkGray
}
