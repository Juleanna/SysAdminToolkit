<#
.SYNOPSIS
    Порівняння конфігурацій двох комп'ютерів.
.DESCRIPTION
    Збирає інформацію з двох ПК (сервіси, ОС, ПЗ) та показує відмінності.
.PARAMETER ComputerName1
    Перший комп'ютер.
.PARAMETER ComputerName2
    Другий комп'ютер.
.PARAMETER ExportHtml
    Зберегти у HTML.
.EXAMPLE
    .\Compare-Configs.ps1 -ComputerName1 "PC-01" -ComputerName2 "PC-02"
#>
param(
    [Parameter(Mandatory=$true)][string]$ComputerName1,
    [Parameter(Mandatory=$true)][string]$ComputerName2,
    [switch]$ExportHtml
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Порівняння: $ComputerName1 vs $ComputerName2" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$gatherScript = {
    $os = Get-CimInstance Win32_OperatingSystem
    $services = Get-Service | Where-Object { $_.StartType -ne 'Disabled' } | Select-Object -ExpandProperty Name | Sort-Object
    $software = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName | Sort-Object
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' }).IPAddress -join ', '
    [PSCustomObject]@{
        OS = "$($os.Caption) $($os.Version)"
        Services = $services
        Software = $software
        IP = $ip
    }
}

try {
    Write-Host "Збираю дані з $ComputerName1..." -ForegroundColor Gray
    $data1 = Invoke-Command -ComputerName $ComputerName1 -ScriptBlock $gatherScript -ErrorAction Stop
    Write-Host "Збираю дані з $ComputerName2..." -ForegroundColor Gray
    $data2 = Invoke-Command -ComputerName $ComputerName2 -ScriptBlock $gatherScript -ErrorAction Stop
} catch {
    Write-Host "Помилка з'єднання: $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Compare-Configs помилка: $($_.Exception.Message)" -Level ERROR
    exit 1
}

$results = [System.Collections.ArrayList]::new()

# ОС
Write-Host "`n--- Операційна система ---" -ForegroundColor Cyan
Write-Host "  $ComputerName1 : $($data1.OS)" -ForegroundColor White
Write-Host "  $ComputerName2 : $($data2.OS)" -ForegroundColor White
if ($data1.OS -ne $data2.OS) { Write-Host "  РІЗНИЦЯ!" -ForegroundColor Yellow }

# Сервіси
Write-Host "`n--- Сервіси (відмінності) ---" -ForegroundColor Cyan
$onlyIn1 = $data1.Services | Where-Object { $_ -notin $data2.Services }
$onlyIn2 = $data2.Services | Where-Object { $_ -notin $data1.Services }
if ($onlyIn1) { $onlyIn1 | ForEach-Object { Write-Host "  + тільки на $ComputerName1 : $_" -ForegroundColor Green; [void]$results.Add([PSCustomObject]@{ Категорія="Сервіс"; Елемент=$_; Де="Тільки $ComputerName1" }) } }
if ($onlyIn2) { $onlyIn2 | ForEach-Object { Write-Host "  + тільки на $ComputerName2 : $_" -ForegroundColor Yellow; [void]$results.Add([PSCustomObject]@{ Категорія="Сервіс"; Елемент=$_; Де="Тільки $ComputerName2" }) } }
if (-not $onlyIn1 -and -not $onlyIn2) { Write-Host "  Однакові." -ForegroundColor Green }

# ПЗ
Write-Host "`n--- Програмне забезпечення (відмінності) ---" -ForegroundColor Cyan
$sw1 = $data1.Software | Where-Object { $_ -notin $data2.Software }
$sw2 = $data2.Software | Where-Object { $_ -notin $data1.Software }
if ($sw1) { $sw1 | ForEach-Object { Write-Host "  + тільки на $ComputerName1 : $_" -ForegroundColor Green; [void]$results.Add([PSCustomObject]@{ Категорія="ПЗ"; Елемент=$_; Де="Тільки $ComputerName1" }) } }
if ($sw2) { $sw2 | ForEach-Object { Write-Host "  + тільки на $ComputerName2 : $_" -ForegroundColor Yellow; [void]$results.Add([PSCustomObject]@{ Категорія="ПЗ"; Елемент=$_; Де="Тільки $ComputerName2" }) } }
if (-not $sw1 -and -not $sw2) { Write-Host "  Однакові." -ForegroundColor Green }

Write-Host "`nВідмінностей: $($results.Count)" -ForegroundColor Cyan

if ($ExportHtml -and $results.Count -gt 0) {
    $path = Join-Path (Get-ToolkitRoot) "Reports\Compare_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    Export-TkReport -Data $results -Path $path -Title "Порівняння $ComputerName1 vs $ComputerName2" -Format HTML
    Write-Host "Звіт: $path" -ForegroundColor Green
}
Write-TkLog "Compare-Configs: $ComputerName1 vs $ComputerName2 — $($results.Count) відмінностей" -Level INFO
