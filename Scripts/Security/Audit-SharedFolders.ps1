<#
.SYNOPSIS
    Аудит спільних SMB-папок та їх дозволів на локальному комп'ютері.

.DESCRIPTION
    Виводить список усіх SMB-спільних папок з деталями доступу: ім'я ресурсу, шлях,
    тип доступу та обліковий запис. За замовчуванням приховує адміністративні ресурси
    (C$, ADMIN$, IPC$ тощо). Використовуйте -IncludeDefault для їх відображення.

.PARAMETER IncludeDefault
    Включити стандартні адміністративні ресурси (C$, ADMIN$, IPC$ тощо) у вивід.

.EXAMPLE
    .\Audit-SharedFolders.ps1
    Показує лише користувацькі спільні папки з дозволами.

.EXAMPLE
    .\Audit-SharedFolders.ps1 -IncludeDefault
    Показує всі спільні папки, включаючи адміністративні.
#>

param(
    [switch]$IncludeDefault
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск аудиту спільних папок SMB" -Level INFO

$defaultShares = @('C$', 'D$', 'E$', 'F$', 'G$', 'ADMIN$', 'IPC$', 'print$')

try {
    $shares = Get-SmbShare -ErrorAction Stop

    if (-not $IncludeDefault) {
        $shares = $shares | Where-Object {
            $_.Name -notin $defaultShares -and $_.Name -notmatch '^[A-Z]\$$'
        }
    }

    if (-not $shares -or @($shares).Count -eq 0) {
        Write-Host "Спільних папок не знайдено." -ForegroundColor Yellow
        Write-TkLog "Спільних папок не знайдено" -Level INFO
        exit 0
    }

    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host "  АУДИТ СПІЛЬНИХ ПАПОК SMB  |  $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray

    $results = @()

    foreach ($share in $shares) {
        Write-Host "`n  Ресурс: $($share.Name)" -ForegroundColor Yellow
        Write-Host "  Шлях:   $($share.Path)" -ForegroundColor Gray
        Write-Host "  Опис:   $($share.Description)" -ForegroundColor Gray

        try {
            $access = Get-SmbShareAccess -Name $share.Name -ErrorAction Stop

            foreach ($ace in $access) {
                $color = switch ($ace.AccessControlType) {
                    'Allow' { 'Green' }
                    'Deny'  { 'Red' }
                    default { 'White' }
                }
                Write-Host ("    {0,-30} {1,-10} {2}" -f $ace.AccountName, $ace.AccessRight, $ace.AccessControlType) -ForegroundColor $color

                $results += [pscustomobject]@{
                    ShareName         = $share.Name
                    Path              = $share.Path
                    Description       = $share.Description
                    AccountName       = $ace.AccountName
                    AccessRight       = $ace.AccessRight
                    AccessControlType = $ace.AccessControlType
                }
            }
        } catch {
            Write-Warning "  Не вдалося отримати дозволи для '$($share.Name)': $($_.Exception.Message)"
            Write-TkLog "Помилка отримання дозволів для '$($share.Name)': $($_.Exception.Message)" -Level WARN
        }
    }

    Write-Host "`n$(("-" * 80))" -ForegroundColor DarkGray
    Write-Host "  Всього ресурсів: $(@($shares).Count)" -ForegroundColor Cyan

    Write-TkLog "Аудит спільних папок завершено. Знайдено ресурсів: $(@($shares).Count)" -Level INFO

} catch {
    Write-Error "Не вдалося отримати список спільних папок: $($_.Exception.Message)"
    Write-TkLog "Критична помилка аудиту SMB: $($_.Exception.Message)" -Level ERROR
    exit 1
}
