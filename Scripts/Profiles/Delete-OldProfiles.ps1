<#
.SYNOPSIS
    Видалення старих профілів користувачів.
.DESCRIPTION
    Знаходить профілі, які не використовувалися понад N днів.
    Без -Force лише показує список (як -WhatIf).
    З -Force або через -WhatIf/-Confirm підтримує ShouldProcess.
.PARAMETER DaysOld
    Кількість днів неактивності. За замовчуванням 90.
.PARAMETER Force
    Виконати видалення без додаткового підтвердження.
.EXAMPLE
    .\Delete-OldProfiles.ps1 -DaysOld 60
    Показує профілі старші за 60 днів.
.EXAMPLE
    .\Delete-OldProfiles.ps1 -DaysOld 60 -Force
    Видаляє профілі старші за 60 днів.
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [int]$DaysOld = 90,
    [switch]$Force
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$cutoff = (Get-Date).AddDays(-[math]::Abs($DaysOld))

$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and
    $_.LocalPath -notlike "*$env:USERNAME*" -and
    $_.LastUseTime -and
    $_.LastUseTime -lt $cutoff
}

if (-not $profiles) {
    Write-Host "Немає профілів старших за $DaysOld днів для видалення." -ForegroundColor Green
    exit 0
}

Write-Host "Знайдено профілів для видалення: $(@($profiles).Count)" -ForegroundColor Yellow
$profiles | ForEach-Object {
    Write-Host "  $($_.LocalPath) — останнє використання: $($_.LastUseTime)"
}

if (-not $Force -and -not $WhatIfPreference) {
    Write-Host "`nДля видалення запустіть з параметром -Force або -Confirm" -ForegroundColor Yellow
    exit 0
}

foreach ($p in $profiles) {
    if ($PSCmdlet.ShouldProcess($p.LocalPath, "Видалити профіль")) {
        try {
            Write-Host "Видаляю профіль: $($p.LocalPath)..."
            Remove-CimInstance $p -ErrorAction Stop
            Write-Host "  Видалено." -ForegroundColor Green
            Write-TkLog "Видалено профіль: $($p.LocalPath)" -Level INFO
        } catch {
            Write-Warning "Не вдалося видалити $($p.LocalPath): $($_.Exception.Message)"
            Write-TkLog "Помилка видалення профілю $($p.LocalPath): $($_.Exception.Message)" -Level ERROR
        }
    }
}
