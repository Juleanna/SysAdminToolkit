<#
.SYNOPSIS
    Генерує звіт про стан комп'ютерних облікових записів Active Directory.
.DESCRIPTION
    Аналізує комп'ютерні об'єкти AD за кількома критеріями:
    - Застарілі комп'ютери (не входили більше N днів)
    - Вимкнені комп'ютерні облікові записи
    - Зведення по операційних системах
    Виводить кольоровий звіт у консоль. За наявності прапорця -ExportHtml
    зберігає HTML-звіт через Export-TkReport.
.PARAMETER DaysInactive
    Кількість днів неактивності для визначення "застарілого" комп'ютера.
    За замовчуванням: 90 днів.
.PARAMETER ExportHtml
    Якщо вказано, експортує результати у HTML-файл у папку Reports.
.EXAMPLE
    .\AD-ComputerReport.ps1
    Генерує звіт з порогом неактивності 90 днів, виводить у консоль.
.EXAMPLE
    .\AD-ComputerReport.ps1 -DaysInactive 60 -ExportHtml
    Генерує звіт з порогом 60 днів та зберігає HTML-файл.
#>
param(
    [int]$DaysInactive = 90,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск AD-ComputerReport (DaysInactive=$DaysInactive, ExportHtml=$ExportHtml)" -Level INFO

# --- Перевірка модуля ActiveDirectory ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Модуль ActiveDirectory не знайдено. Встановіть RSAT." -ForegroundColor Red
    Write-TkLog "Модуль ActiveDirectory не знайдено" -Level ERROR
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

try {
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "       ЗВIТ ПРО КОМП'ЮТЕРНI ОБ'ЄКТИ AD" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Поріг неактивності: $DaysInactive днів" -ForegroundColor Cyan
    Write-Host "Дата звіту: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Cyan

    $cutoffDate = (Get-Date).AddDays(-$DaysInactive)

    # -------------------------------------------------------
    #  Секція 1: Застарілі комп'ютери
    # -------------------------------------------------------
    Write-Host "--- Застарілі комп'ютери (не входили > $DaysInactive днів) ---" -ForegroundColor Yellow
    try {
        $staleComputers = Get-ADComputer -Filter {
            LastLogonDate -lt $cutoffDate -and Enabled -eq $true
        } -Properties LastLogonDate, OperatingSystem, OperatingSystemVersion, Description, IPv4Address |
            Select-Object Name,
                @{N='OS';         E={ $_.OperatingSystem }},
                @{N='OSVersion';  E={ $_.OperatingSystemVersion }},
                @{N='IP';         E={ $_.IPv4Address }},
                Description,
                @{N='LastLogon';  E={ if ($_.LastLogonDate) { $_.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Ніколи' } }},
                @{N='DaysAgo';    E={ if ($_.LastLogonDate) { [math]::Round(((Get-Date) - $_.LastLogonDate).TotalDays) } else { 'N/A' } }}

        if ($staleComputers -and @($staleComputers).Count -gt 0) {
            $staleComputers | Format-Table -AutoSize
            Write-Host "Знайдено застарілих: $(@($staleComputers).Count)" -ForegroundColor Red
        } else {
            Write-Host "Застарілих комп'ютерів не знайдено." -ForegroundColor Green
            $staleComputers = @()
        }
    } catch {
        Write-Host "Помилка отримання застарілих комп'ютерів: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції Stale: $($_.Exception.Message)" -Level ERROR
        $staleComputers = @()
    }

    # -------------------------------------------------------
    #  Секція 2: Вимкнені комп'ютери
    # -------------------------------------------------------
    Write-Host "`n--- Вимкнені комп'ютерні облікові записи ---" -ForegroundColor Yellow
    try {
        $disabledComputers = Get-ADComputer -Filter { Enabled -eq $false } `
            -Properties OperatingSystem, Description, WhenChanged |
            Select-Object Name,
                @{N='OS';          E={ $_.OperatingSystem }},
                Description,
                @{N='WhenChanged'; E={ $_.WhenChanged.ToString('yyyy-MM-dd') }}

        if ($disabledComputers -and @($disabledComputers).Count -gt 0) {
            $disabledComputers | Format-Table -AutoSize
            Write-Host "Вимкнених: $(@($disabledComputers).Count)" -ForegroundColor Yellow
        } else {
            Write-Host "Вимкнених комп'ютерних записів немає." -ForegroundColor Green
            $disabledComputers = @()
        }
    } catch {
        Write-Host "Помилка отримання вимкнених комп'ютерів: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції Disabled: $($_.Exception.Message)" -Level ERROR
        $disabledComputers = @()
    }

    # -------------------------------------------------------
    #  Секція 3: Зведення по операційних системах
    # -------------------------------------------------------
    Write-Host "`n--- Зведення по операційних системах ---" -ForegroundColor Yellow
    try {
        $allComputers = Get-ADComputer -Filter * -Properties OperatingSystem, Enabled |
            Where-Object { $_.Enabled -eq $true }

        $osSummary = $allComputers | Group-Object -Property OperatingSystem |
            Select-Object @{N='ОС'; E={ if ($_.Name) { $_.Name } else { '(Не визначено)' } }},
                @{N='Кількість'; E={ $_.Count }} |
            Sort-Object 'Кількість' -Descending

        if ($osSummary -and @($osSummary).Count -gt 0) {
            $osSummary | Format-Table -AutoSize
            Write-Host "Всього активних комп'ютерів: $(@($allComputers).Count)" -ForegroundColor Cyan
        } else {
            Write-Host "Не вдалося отримати зведення по ОС." -ForegroundColor Yellow
            $osSummary = @()
        }
    } catch {
        Write-Host "Помилка отримання зведення ОС: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції OS Summary: $($_.Exception.Message)" -Level ERROR
        $osSummary = @()
    }

    # -------------------------------------------------------
    #  Підсумок
    # -------------------------------------------------------
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                     ПIДСУМОК" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Застарілих (>$DaysInactive днів): " -NoNewline; Write-Host "$(@($staleComputers).Count)" -ForegroundColor $(if (@($staleComputers).Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Вимкнених:                       " -NoNewline; Write-Host "$(@($disabledComputers).Count)" -ForegroundColor $(if (@($disabledComputers).Count -gt 0) { 'Yellow' } else { 'Green' })
    if ($osSummary -and @($osSummary).Count -gt 0) {
        Write-Host "Унікальних ОС:                   " -NoNewline; Write-Host "$(@($osSummary).Count)" -ForegroundColor Cyan
    }

    # -------------------------------------------------------
    #  Експорт HTML
    # -------------------------------------------------------
    if ($ExportHtml) {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $reportPath = Join-Path $reportDir ("AD-ComputerReport_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

        $allData = @()
        foreach ($c in $staleComputers)    { $allData += [pscustomobject]@{ Категорія='Застарілий'; Ім_я=$c.Name; ОС=$c.OS; IP=$c.IP; Останній_вхід=$c.LastLogon; Днів=$c.DaysAgo } }
        foreach ($c in $disabledComputers) { $allData += [pscustomobject]@{ Категорія='Вимкнений';  Ім_я=$c.Name; ОС=$c.OS; IP='-';   Останній_вхід=$c.WhenChanged; Днів='-' } }

        Export-TkReport -Data $allData -Path $reportPath -Title "AD Computer Report" -Format HTML
        Write-Host "`nHTML-звіт збережено: $reportPath" -ForegroundColor Green
    }

    Write-TkLog "AD-ComputerReport завершено успішно" -Level INFO

} catch {
    $errMsg = "Критична помилка AD-ComputerReport: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
