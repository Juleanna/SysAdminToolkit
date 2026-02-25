param(
    [Parameter(Mandatory = $true)]
    [string]$CertThumbprint
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Assert-Administrator

$ErrorActionPreference = 'Stop'

# ============================================================
#  Заголовок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Підпис скриптів сертифікатом CodeSigning" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$root = Get-ToolkitRoot

# ============================================================
#  1. Отримання сертифікату
# ============================================================

Write-Host "  [*] Пошук сертифікату: $CertThumbprint" -ForegroundColor Cyan

$cert = $null

# Пошук у CurrentUser
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Thumbprint -eq $CertThumbprint }

# Пошук у LocalMachine
if (-not $cert) {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $CertThumbprint }
}

if (-not $cert) {
    Write-Host "  [ПОМИЛКА] Сертифікат з Thumbprint '$CertThumbprint' не знайдено." -ForegroundColor Red
    Write-Host "  Перевірте Cert:\CurrentUser\My та Cert:\LocalMachine\My" -ForegroundColor Yellow
    Write-TkLog "Sign-Scripts: сертифікат $CertThumbprint не знайдено" -Level ERROR
    exit 1
}

Write-Host "  [OK] Сертифікат знайдено: $($cert.Subject)" -ForegroundColor Green

# ============================================================
#  2. Перевірка типу сертифікату
# ============================================================

Write-Host "  [*] Перевірка призначення сертифікату..." -ForegroundColor Cyan

$isCodeSigning = $cert.EnhancedKeyUsageList |
    Where-Object { $_.FriendlyName -eq 'Code Signing' -or $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' }

if (-not $isCodeSigning) {
    Write-Host "  [ПОМИЛКА] Сертифікат не має призначення 'Code Signing'." -ForegroundColor Red
    Write-Host "  Subject:    $($cert.Subject)" -ForegroundColor Gray
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "  EKU:        $(($cert.EnhancedKeyUsageList | Select-Object -ExpandProperty FriendlyName) -join ', ')" -ForegroundColor Gray
    Write-TkLog "Sign-Scripts: сертифікат $CertThumbprint не є CodeSigning" -Level ERROR
    exit 1
}

Write-Host "  [OK] Сертифікат має призначення Code Signing" -ForegroundColor Green

# Перевірка терміну дії
if ($cert.NotAfter -lt (Get-Date)) {
    Write-Host "  [ПОМИЛКА] Сертифікат прострочений! Дійсний до: $($cert.NotAfter)" -ForegroundColor Red
    Write-TkLog "Sign-Scripts: сертифікат прострочений (до $($cert.NotAfter))" -Level ERROR
    exit 1
}

$daysLeft = ($cert.NotAfter - (Get-Date)).Days
if ($daysLeft -lt 30) {
    Write-Host "  [УВАГА] Сертифікат спливає через $daysLeft днів ($($cert.NotAfter))" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] Дійсний до: $($cert.NotAfter) ($daysLeft днів)" -ForegroundColor Green
}

# ============================================================
#  3. Пошук скриптів для підпису
# ============================================================

Write-Host ""
Write-Host "  [*] Пошук файлів .ps1 та .psm1 у $root..." -ForegroundColor Cyan

$files = Get-ChildItem -Path $root -Recurse -Include "*.ps1", "*.psm1" -File |
    Where-Object { $_.FullName -notlike "*\Config_Backup_*" }

if ($files.Count -eq 0) {
    Write-Host "  [УВАГА] Файлів для підпису не знайдено." -ForegroundColor Yellow
    exit 0
}

Write-Host "  [OK] Знайдено файлів: $($files.Count)" -ForegroundColor Green
Write-Host ""

# ============================================================
#  4. Підпис скриптів
# ============================================================

$signed = 0
$skipped = 0
$failed = 0

foreach ($file in $files) {
    $relativePath = $file.FullName.Replace($root, '').TrimStart('\')

    try {
        # Перевіряємо поточний підпис
        $currentSig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue

        if ($currentSig -and $currentSig.Status -eq 'Valid' -and
            $currentSig.SignerCertificate.Thumbprint -eq $CertThumbprint) {
            Write-Host "    [--] $relativePath (вже підписано)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        # Підпис файлу
        $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -ErrorAction Stop

        if ($result.Status -eq 'Valid') {
            Write-Host "    [OK] $relativePath" -ForegroundColor Green
            $signed++
        } else {
            Write-Host "    [!]  $relativePath -- статус: $($result.Status)" -ForegroundColor Yellow
            $signed++
        }
    } catch {
        Write-Host "    [X]  $relativePath -- $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# ============================================================
#  Підсумок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Результати підпису" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Підписано:  $signed" -ForegroundColor Green
Write-Host "  Пропущено:  $skipped" -ForegroundColor DarkGray
Write-Host "  Помилок:    $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Всього:     $($files.Count)" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-TkLog "Sign-Scripts: підписано=$signed, пропущено=$skipped, помилок=$failed (серт: $($cert.Subject))" -Level INFO

if ($failed -gt 0) {
    Write-Host "  Деякі файли не вдалося підписати. Перевірте помилки вище." -ForegroundColor Yellow
}
