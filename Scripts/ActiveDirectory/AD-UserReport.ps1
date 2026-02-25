<#
.SYNOPSIS
    Генерує звіт про стан облікових записів користувачів Active Directory.
.DESCRIPTION
    Аналізує облікові записи користувачів AD за кількома критеріями:
    - Неактивні користувачі (не входили більше N днів)
    - Заблоковані облікові записи (LockedOut)
    - Облікові записи з простроченими паролями (PasswordExpired)
    - Вимкнені облікові записи (Disabled)
    Виводить кольоровий звіт у консоль. За наявності прапорця -ExportHtml
    зберігає HTML-звіт через Export-TkReport.
.PARAMETER DaysInactive
    Кількість днів неактивності для визначення "неактивного" користувача.
    За замовчуванням: 90 днів.
.PARAMETER ExportHtml
    Якщо вказано, експортує результати у HTML-файл у папку Reports.
.EXAMPLE
    .\AD-UserReport.ps1
    Генерує звіт з порогом неактивності 90 днів, виводить у консоль.
.EXAMPLE
    .\AD-UserReport.ps1 -DaysInactive 60 -ExportHtml
    Генерує звіт з порогом 60 днів та зберігає HTML-файл.
#>
param(
    [int]$DaysInactive = 90,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск AD-UserReport (DaysInactive=$DaysInactive, ExportHtml=$ExportHtml)" -Level INFO

# --- Перевірка модуля ActiveDirectory ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Модуль ActiveDirectory не знайдено. Встановіть RSAT." -ForegroundColor Red
    Write-TkLog "Модуль ActiveDirectory не знайдено" -Level ERROR
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

try {
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "         ЗВIТ ПРО ОБЛIКОВI ЗАПИСИ КОРИСТУВАЧIВ AD" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Поріг неактивності: $DaysInactive днів" -ForegroundColor Cyan
    Write-Host "Дата звіту: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Cyan

    $cutoffDate = (Get-Date).AddDays(-$DaysInactive)

    # -------------------------------------------------------
    #  Секція 1: Неактивні користувачі
    # -------------------------------------------------------
    Write-Host "--- Неактивні користувачі (не входили > $DaysInactive днів) ---" -ForegroundColor Yellow
    try {
        $inactiveUsers = Get-ADUser -Filter {
            LastLogonDate -lt $cutoffDate -and Enabled -eq $true
        } -Properties LastLogonDate, DisplayName, Department, Title |
            Select-Object Name, DisplayName, SamAccountName, Department, Title,
                @{N='LastLogon'; E={ if ($_.LastLogonDate) { $_.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Ніколи' } }},
                @{N='DaysAgo';   E={ if ($_.LastLogonDate) { [math]::Round(((Get-Date) - $_.LastLogonDate).TotalDays) } else { 'N/A' } }}

        if ($inactiveUsers -and @($inactiveUsers).Count -gt 0) {
            $inactiveUsers | Format-Table -AutoSize
            Write-Host "Знайдено неактивних: $(@($inactiveUsers).Count)" -ForegroundColor Red
        } else {
            Write-Host "Неактивних користувачів не знайдено." -ForegroundColor Green
            $inactiveUsers = @()
        }
    } catch {
        Write-Host "Помилка отримання неактивних користувачів: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції Inactive: $($_.Exception.Message)" -Level ERROR
        $inactiveUsers = @()
    }

    # -------------------------------------------------------
    #  Секція 2: Заблоковані облікові записи
    # -------------------------------------------------------
    Write-Host "`n--- Заблоковані облікові записи ---" -ForegroundColor Yellow
    try {
        $lockedUsers = Search-ADAccount -LockedOut -UsersOnly |
            Get-ADUser -Properties DisplayName, LockedOut, LockoutTime, Department |
            Select-Object Name, DisplayName, SamAccountName, Department,
                @{N='LockoutTime'; E={ if ($_.LockoutTime) { [datetime]::FromFileTime($_.LockoutTime).ToString('yyyy-MM-dd HH:mm') } else { '-' } }}

        if ($lockedUsers -and @($lockedUsers).Count -gt 0) {
            $lockedUsers | Format-Table -AutoSize
            Write-Host "Заблокованих: $(@($lockedUsers).Count)" -ForegroundColor Red
        } else {
            Write-Host "Заблокованих облікових записів немає." -ForegroundColor Green
            $lockedUsers = @()
        }
    } catch {
        Write-Host "Помилка отримання заблокованих: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції Locked: $($_.Exception.Message)" -Level ERROR
        $lockedUsers = @()
    }

    # -------------------------------------------------------
    #  Секція 3: Прострочені паролі
    # -------------------------------------------------------
    Write-Host "`n--- Облікові записи з простроченими паролями ---" -ForegroundColor Yellow
    try {
        $expiredPwdUsers = Get-ADUser -Filter { PasswordExpired -eq $true -and Enabled -eq $true } `
            -Properties DisplayName, PasswordExpired, PasswordLastSet, Department |
            Select-Object Name, DisplayName, SamAccountName, Department,
                @{N='PasswordLastSet'; E={ if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('yyyy-MM-dd') } else { 'Ніколи' } }}

        if ($expiredPwdUsers -and @($expiredPwdUsers).Count -gt 0) {
            $expiredPwdUsers | Format-Table -AutoSize
            Write-Host "З простроченими паролями: $(@($expiredPwdUsers).Count)" -ForegroundColor Red
        } else {
            Write-Host "Облікових записів з простроченими паролями немає." -ForegroundColor Green
            $expiredPwdUsers = @()
        }
    } catch {
        Write-Host "Помилка отримання прострочених паролів: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції ExpiredPwd: $($_.Exception.Message)" -Level ERROR
        $expiredPwdUsers = @()
    }

    # -------------------------------------------------------
    #  Секція 4: Вимкнені облікові записи
    # -------------------------------------------------------
    Write-Host "`n--- Вимкнені облікові записи ---" -ForegroundColor Yellow
    try {
        $disabledUsers = Get-ADUser -Filter { Enabled -eq $false } `
            -Properties DisplayName, Department, WhenChanged |
            Select-Object Name, DisplayName, SamAccountName, Department,
                @{N='WhenChanged'; E={ $_.WhenChanged.ToString('yyyy-MM-dd') }}

        if ($disabledUsers -and @($disabledUsers).Count -gt 0) {
            $disabledUsers | Format-Table -AutoSize
            Write-Host "Вимкнених: $(@($disabledUsers).Count)" -ForegroundColor Yellow
        } else {
            Write-Host "Вимкнених облікових записів немає." -ForegroundColor Green
            $disabledUsers = @()
        }
    } catch {
        Write-Host "Помилка отримання вимкнених: $($_.Exception.Message)" -ForegroundColor Red
        Write-TkLog "Помилка секції Disabled: $($_.Exception.Message)" -Level ERROR
        $disabledUsers = @()
    }

    # -------------------------------------------------------
    #  Підсумок
    # -------------------------------------------------------
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                     ПIДСУМОК" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Неактивних (>$DaysInactive днів): " -NoNewline; Write-Host "$(@($inactiveUsers).Count)" -ForegroundColor $(if (@($inactiveUsers).Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Заблокованих:                     " -NoNewline; Write-Host "$(@($lockedUsers).Count)" -ForegroundColor $(if (@($lockedUsers).Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Прострочені паролі:               " -NoNewline; Write-Host "$(@($expiredPwdUsers).Count)" -ForegroundColor $(if (@($expiredPwdUsers).Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Вимкнених:                        " -NoNewline; Write-Host "$(@($disabledUsers).Count)" -ForegroundColor $(if (@($disabledUsers).Count -gt 0) { 'Yellow' } else { 'Green' })

    # -------------------------------------------------------
    #  Експорт HTML
    # -------------------------------------------------------
    if ($ExportHtml) {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $reportPath = Join-Path $reportDir ("AD-UserReport_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

        $allData = @()
        foreach ($u in $inactiveUsers)   { $allData += [pscustomobject]@{ Категорія='Неактивний';    Ім_я=$u.Name; Логін=$u.SamAccountName; Відділ=$u.Department; Деталі=$u.LastLogon } }
        foreach ($u in $lockedUsers)     { $allData += [pscustomobject]@{ Категорія='Заблокований';  Ім_я=$u.Name; Логін=$u.SamAccountName; Відділ=$u.Department; Деталі=$u.LockoutTime } }
        foreach ($u in $expiredPwdUsers) { $allData += [pscustomobject]@{ Категорія='Прострочений пароль'; Ім_я=$u.Name; Логін=$u.SamAccountName; Відділ=$u.Department; Деталі=$u.PasswordLastSet } }
        foreach ($u in $disabledUsers)   { $allData += [pscustomobject]@{ Категорія='Вимкнений';     Ім_я=$u.Name; Логін=$u.SamAccountName; Відділ=$u.Department; Деталі=$u.WhenChanged } }

        Export-TkReport -Data $allData -Path $reportPath -Title "AD User Report" -Format HTML
        Write-Host "`nHTML-звіт збережено: $reportPath" -ForegroundColor Green
    }

    Write-TkLog "AD-UserReport завершено успішно" -Level INFO

} catch {
    $errMsg = "Критична помилка AD-UserReport: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
