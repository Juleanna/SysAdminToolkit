<#
.SYNOPSIS
    Показує звіт про використання дискового простору профілями користувачів.

.DESCRIPTION
    Сканує папки у C:\Users\*, обчислює розмір кожного профілю за допомогою
    Get-ChildItem -Recurse та Measure-Object, сортує за розміром (від більшого).
    Відображає ім'я користувача, розмір у МБ та дату останнього доступу.

.EXAMPLE
    .\Disk-QuotaReport.ps1
    Виводить таблицю використання простору профілями користувачів.
#>

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Квоти дискового простору (профілі)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$usersPath = "C:\Users"

if (-not (Test-Path $usersPath)) {
    Write-Host "[ПОМИЛКА] Шлях $usersPath не знайдено." -ForegroundColor Red
    Write-TkLog "Disk-QuotaReport: Шлях $usersPath не знайдено" -Level ERROR
    exit 1
}

try {
    $profiles = Get-ChildItem -Path $usersPath -Directory -ErrorAction Stop |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
} catch {
    Write-Host "[ПОМИЛКА] Не вдалося отримати список профілів: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Disk-QuotaReport: Помилка читання $usersPath`: $($_.Exception.Message)" -Level ERROR
    exit 1
}

if (-not $profiles) {
    Write-Host "Профілів користувачів не знайдено." -ForegroundColor Yellow
    exit 0
}

Write-Host "Сканування профілів... Це може зайняти деякий час." -ForegroundColor Gray
Write-Host ""

$results = @()

foreach ($profile in $profiles) {
    $userName = $profile.Name
    $profilePath = $profile.FullName

    try {
        $measurement = Get-ChildItem -Path $profilePath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum

        $sizeMB = if ($measurement.Sum) {
            [math]::Round($measurement.Sum / 1MB, 2)
        } else {
            0
        }

        $lastAccess = $profile.LastWriteTime

        $results += [pscustomobject]@{
            "Користувач"      = $userName
            "Розмір МБ"       = $sizeMB
            "Останній доступ" = $lastAccess.ToString('yyyy-MM-dd HH:mm')
        }
    } catch {
        Write-Host "  [УВАГА] Не вдалося просканувати профіль '$userName': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-TkLog "Disk-QuotaReport: Помилка сканування профілю '$userName': $($_.Exception.Message)" -Level WARN
    }
}

if (-not $results) {
    Write-Host "Не вдалося отримати дані жодного профілю." -ForegroundColor Yellow
    exit 0
}

# Сортування за розміром (від більшого)
$results = $results | Sort-Object -Property "Розмір МБ" -Descending

# Заголовок таблиці
$header = "{0,-25} {1,12} {2,-20}" -f "Користувач", "Розмір МБ", "Останній доступ"
Write-Host $header -ForegroundColor White
Write-Host ("-" * 60) -ForegroundColor Gray

foreach ($row in $results) {
    $sizeMB = $row."Розмір МБ"
    $line = "{0,-25} {1,12} {2,-20}" -f $row."Користувач", $sizeMB, $row."Останній доступ"

    if ($sizeMB -ge 10000) {
        Write-Host $line -ForegroundColor Red
    } elseif ($sizeMB -ge 5000) {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Green
    }
}

# Загальний підсумок
$totalMB = [math]::Round(($results | Measure-Object -Property "Розмір МБ" -Sum).Sum, 2)
$totalGB = [math]::Round($totalMB / 1024, 2)

Write-Host ""
Write-Host ("-" * 60) -ForegroundColor Gray
Write-Host "Всього профілів: $($results.Count)" -ForegroundColor Cyan
Write-Host "Загальний розмір: $totalMB МБ ($totalGB ГБ)" -ForegroundColor Cyan

Write-TkLog "Disk-QuotaReport: Просканувано $($results.Count) профіл(ів), загальний розмір $totalGB ГБ" -Level INFO
