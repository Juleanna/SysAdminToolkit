<#
.SYNOPSIS
    Перевіряє термін дії сертифікатів у сховищі LocalMachine\My.
.DESCRIPTION
    Аналізує всі сертифікати у вказаному сховищі та показує інформацію про термін дії.
    Протерміновані сертифікати виділяються червоним, ті що скоро закінчуються — жовтим.
.PARAMETER WarnDays
    Кількість днів до закінчення терміну для попередження. За замовчуванням 30.
.PARAMETER ExportHtml
    Перемикач для експорту звіту у HTML-файл.
.EXAMPLE
    .\Cert-ExpiryCheck.ps1
    Перевіряє сертифікати з порогом попередження 30 днів.
.EXAMPLE
    .\Cert-ExpiryCheck.ps1 -WarnDays 60 -ExportHtml
    Перевіряє сертифікати з порогом 60 днів та експортує звіт у HTML.
#>
param(
    [int]$WarnDays = 30,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск перевірки сертифікатів (WarnDays=$WarnDays)" -Level INFO

try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $certs = $store.Certificates
    $store.Close()
} catch {
    Write-TkLog "Не вдалося відкрити сховище сертифікатів: $($_.Exception.Message)" -Level ERROR
    Write-Error "Не вдалося відкрити сховище сертифікатів: $($_.Exception.Message)"
    exit 1
}

if ($certs.Count -eq 0) {
    Write-Host "Сертифікати у сховищі LocalMachine\My не знайдено." -ForegroundColor Yellow
    Write-TkLog "Сертифікати не знайдено у LocalMachine\My" -Level WARN
    exit 0
}

$now = Get-Date
$results = @()

Write-Host "`n=== Перевірка сертифікатів (LocalMachine\My) ===" -ForegroundColor Cyan
Write-Host "Поріг попередження: $WarnDays днів`n" -ForegroundColor Cyan

foreach ($cert in $certs) {
    try {
        $daysLeft = [math]::Floor(($cert.NotAfter - $now).TotalDays)
        $subject = $cert.Subject
        if ($subject.Length -gt 60) { $subject = $subject.Substring(0, 57) + "..." }

        $obj = [pscustomobject]@{
            Subject    = $subject
            Thumbprint = $cert.Thumbprint
            NotAfter   = $cert.NotAfter.ToString("yyyy-MM-dd")
            DaysLeft   = $daysLeft
            Status     = if ($daysLeft -lt 0) { "Протермінований" } elseif ($daysLeft -le $WarnDays) { "Скоро закінчується" } else { "OK" }
        }
        $results += $obj

        $color = if ($daysLeft -lt 0) {
            "Red"
        } elseif ($daysLeft -le $WarnDays) {
            "Yellow"
        } else {
            "Green"
        }

        $line = "{0,-62} {1,-12} Днів: {2}" -f $subject, $cert.NotAfter.ToString("yyyy-MM-dd"), $daysLeft
        Write-Host $line -ForegroundColor $color
    } catch {
        Write-TkLog "Помилка обробки сертифіката: $($_.Exception.Message)" -Level WARN
        Write-Warning "Помилка обробки сертифіката: $($_.Exception.Message)"
    }
}

# Підсумок
$expired = ($results | Where-Object { $_.DaysLeft -lt 0 }).Count
$warning = ($results | Where-Object { $_.DaysLeft -ge 0 -and $_.DaysLeft -le $WarnDays }).Count
$ok = ($results | Where-Object { $_.DaysLeft -gt $WarnDays }).Count

Write-Host "`n--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Всього: $($results.Count) | " -NoNewline
Write-Host "OK: $ok" -ForegroundColor Green -NoNewline
Write-Host " | " -NoNewline
Write-Host "Попередження: $warning" -ForegroundColor Yellow -NoNewline
Write-Host " | " -NoNewline
Write-Host "Протерміновані: $expired" -ForegroundColor Red

Write-TkLog "Перевірка сертифікатів завершена. Всього: $($results.Count), OK: $ok, Попередження: $warning, Протерміновані: $expired" -Level INFO

if ($ExportHtml) {
    try {
        $reportDir = Join-Path (Get-ToolkitRoot) "Reports"
        if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $reportPath = Join-Path $reportDir ("CertExpiry_{0}.html" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Export-TkReport -Data $results -Path $reportPath -Title "Звіт про сертифікати" -Format HTML
        Write-Host "`nHTML-звіт збережено: $reportPath" -ForegroundColor Green
    } catch {
        Write-TkLog "Не вдалося експортувати HTML-звіт: $($_.Exception.Message)" -Level ERROR
        Write-Warning "Не вдалося експортувати HTML-звіт: $($_.Exception.Message)"
    }
}
