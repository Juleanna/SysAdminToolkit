<#
.SYNOPSIS
    Перевірка локальних акаунтів на слабкі паролі.
.DESCRIPTION
    Шукає: акаунти без пароля, з необов'язковим паролем, паролем що ніколи не спливає, старим паролем.
.EXAMPLE
    .\Check-WeakPasswords.ps1
#>
param()

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Аудит слабких паролів" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$riskCount = 0
$users = Get-LocalUser

# Пароль не обов'язковий
Write-Host "--- Акаунти де пароль необов'язковий ---" -ForegroundColor Yellow
$noReq = $users | Where-Object { $_.PasswordRequired -eq $false -and $_.Enabled }
if ($noReq) {
    $noReq | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Red; $riskCount++ }
} else { Write-Host "  Не знайдено." -ForegroundColor Green }

Write-Host ""

# Пароль ніколи не спливає
Write-Host "--- Пароль ніколи не спливає ---" -ForegroundColor Yellow
$neverExp = $users | Where-Object { $_.PasswordNeverExpires -eq $true -and $_.Enabled }
if ($neverExp) {
    $neverExp | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Yellow; $riskCount++ }
} else { Write-Host "  Не знайдено." -ForegroundColor Green }

Write-Host ""

# Старий пароль (>90 днів)
Write-Host "--- Пароль не змінювався >90 днів ---" -ForegroundColor Yellow
$cutoff = (Get-Date).AddDays(-90)
$oldPwd = $users | Where-Object { $_.Enabled -and $_.PasswordLastSet -and $_.PasswordLastSet -lt $cutoff }
if ($oldPwd) {
    $oldPwd | ForEach-Object {
        Write-Host "  $($_.Name) — останнє оновлення: $($_.PasswordLastSet)" -ForegroundColor Yellow
        $riskCount++
    }
} else { Write-Host "  Не знайдено." -ForegroundColor Green }

Write-Host ""

# Спроба виявити порожні паролі через ADSI
Write-Host "--- Спроба виявлення порожніх паролів ---" -ForegroundColor Yellow
$emptyPwdFound = 0
foreach ($u in ($users | Where-Object { $_.Enabled })) {
    try {
        $adsiUser = [ADSI]"WinNT://./$($u.Name),user"
        $adsiUser.Invoke("ChangePassword", "", "TempP@ss123!")
        $adsiUser.Invoke("ChangePassword", "TempP@ss123!", "")
        Write-Host "  $($u.Name) — ПОРОЖНІЙ ПАРОЛЬ!" -ForegroundColor Red
        $emptyPwdFound++; $riskCount++
    } catch {
        # Пароль не порожній або доступ заборонено
    }
}
if ($emptyPwdFound -eq 0) { Write-Host "  Не знайдено (або доступ обмежено)." -ForegroundColor Green }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($riskCount -gt 0) {
    Write-Host "  Знайдено ризиків: $riskCount" -ForegroundColor Red
} else {
    Write-Host "  Ризиків не знайдено." -ForegroundColor Green
}
Write-TkLog "Check-WeakPasswords: знайдено $riskCount ризиків" -Level $(if($riskCount -gt 0){"WARN"}else{"INFO"})
