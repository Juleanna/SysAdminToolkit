<#
.SYNOPSIS
    Рекурсивний аудит NTFS-прав на папці.
.DESCRIPTION
    Сканує ACL для файлів та папок до заданої глибини. Виділяє небезпечні дозволи.
.PARAMETER Path
    Шлях до папки для аудиту.
.PARAMETER Depth
    Глибина рекурсії. За замовчуванням 2.
.PARAMETER ExportHtml
    Зберегти звіт у HTML.
.EXAMPLE
    .\Audit-Permissions.ps1 -Path "D:\SharedFolder" -Depth 3
#>
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$Depth = 2,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
Assert-Administrator

if (-not (Test-Path $Path)) {
    Write-Host "Шлях не знайдено: $Path" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Аудит NTFS-прав: $Path" -ForegroundColor Cyan
Write-Host "  Глибина: $Depth" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$results = [System.Collections.ArrayList]::new()

function Scan-Acl {
    param([string]$ItemPath, [int]$CurrentDepth, [int]$MaxDepth)
    if ($CurrentDepth -gt $MaxDepth) { return }
    try {
        $acl = Get-Acl -Path $ItemPath -ErrorAction Stop
        foreach ($access in $acl.Access) {
            $identity = $access.IdentityReference.ToString()
            $rights = $access.FileSystemRights.ToString()
            $type = $access.AccessControlType.ToString()

            $color = "White"
            if ($identity -match '(Everyone|Все|Усі)' -and $rights -match 'FullControl') { $color = "Red" }
            elseif ($identity -match '(Users|Користувачі)' -and $rights -match 'FullControl') { $color = "Yellow" }
            elseif ($identity -match 'Administrator') { $color = "Green" }

            Write-Host ("  {0}" -f $ItemPath) -ForegroundColor Gray -NoNewline
            Write-Host (" | {0} | {1} | {2}" -f $identity, $rights, $type) -ForegroundColor $color

            [void]$results.Add([PSCustomObject]@{
                Шлях=$ItemPath; Власник=$acl.Owner; Суб_єкт=$identity; Права=$rights; Тип=$type
            })
        }
    } catch {
        Write-Host "  Помилка ACL: $ItemPath — $($_.Exception.Message)" -ForegroundColor Red
    }
    if ($CurrentDepth -lt $MaxDepth) {
        Get-ChildItem -Path $ItemPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Scan-Acl -ItemPath $_.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
        }
    }
}

Scan-Acl -ItemPath $Path -CurrentDepth 0 -MaxDepth $Depth

Write-Host "`nВсього записів ACL: $($results.Count)" -ForegroundColor Cyan

if ($ExportHtml -and $results.Count -gt 0) {
    $reportPath = Join-Path (Get-ToolkitRoot) "Reports\Audit-Permissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    Export-TkReport -Data $results -Path $reportPath -Title "Аудит NTFS-прав" -Format HTML
    Write-Host "Звіт: $reportPath" -ForegroundColor Green
}
Write-TkLog "Audit-Permissions: $Path — $($results.Count) записів" -Level INFO
