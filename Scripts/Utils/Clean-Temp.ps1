<#
.SYNOPSIS
    Очищення тимчасових файлів системи.
.DESCRIPTION
    Видаляє файли з TEMP та Windows\Temp. Підтримує -WhatIf.
.PARAMETER WhatIf
    Показати що буде видалено без фактичного видалення.
.EXAMPLE
    .\Clean-Temp.ps1
    .\Clean-Temp.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param()

$paths = @(
    $env:TEMP,
    "$env:WINDIR\Temp"
)

$totalFreed = 0
foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }
    $items = Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue
    $sizeBefore = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

    if ($PSCmdlet.ShouldProcess($p, "Очистити тимчасові файли")) {
        Write-Host "Очищення $p..."
        $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        $sizeAfter = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $freed = [math]::Round((($sizeBefore - $sizeAfter) / 1MB), 1)
        if ($freed -gt 0) { $totalFreed += $freed }
    } else {
        $sizeMB = [math]::Round(($sizeBefore / 1MB), 1)
        Write-Host "WhatIf: Було б очищено $p (~$sizeMB MB)" -ForegroundColor Yellow
    }
}

Write-Host "Тимчасові файли очищено. Звільнено ~${totalFreed} MB." -ForegroundColor Green
