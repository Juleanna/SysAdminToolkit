<#
.SYNOPSIS
    Отримує DNS-записи для вказаного доменного імені.
.DESCRIPTION
    Використовує командлет Resolve-DnsName для отримання DNS-записів заданого типу.
    Підтримує типи: A, AAAA, MX, NS, CNAME, TXT, SOA.
    Результати виводяться у форматі таблиці з кольоровим оформленням.
    Помилки обробляються через try/catch з дружніми повідомленнями українською.
.PARAMETER DomainName
    Доменне ім'я для DNS-запиту. Обов'язковий параметр.
.PARAMETER RecordType
    Тип DNS-запису для запиту. Допустимі значення: A, AAAA, MX, NS, CNAME, TXT, SOA.
    За замовчуванням: A.
.EXAMPLE
    .\Get-DNSRecords.ps1 -DomainName "google.com"
    Показує A-записи для домену google.com.
.EXAMPLE
    .\Get-DNSRecords.ps1 -DomainName "example.com" -RecordType MX
    Показує MX-записи для домену example.com.
.EXAMPLE
    .\Get-DNSRecords.ps1 -DomainName "example.com" -RecordType TXT
    Показує TXT-записи для домену example.com.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [ValidateSet('A', 'AAAA', 'MX', 'NS', 'CNAME', 'TXT', 'SOA')]
    [string]$RecordType = 'A'
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "DNS-запит для '$DomainName' (тип: $RecordType)" -Level INFO

Write-Host "`n=== DNS-записи: $DomainName (тип: $RecordType) ===" -ForegroundColor Cyan
Write-Host ""

try {
    $records = Resolve-DnsName -Name $DomainName -Type $RecordType -ErrorAction Stop
} catch [System.ComponentModel.Win32Exception] {
    $msg = "Не вдалося знайти DNS-записи для '$DomainName': домен не існує або DNS-сервер недоступний."
    Write-Host $msg -ForegroundColor Red
    Write-TkLog $msg -Level ERROR
    exit 1
} catch {
    $msg = "Помилка DNS-запиту для '$DomainName': $($_.Exception.Message)"
    Write-Host $msg -ForegroundColor Red
    Write-TkLog $msg -Level ERROR
    exit 1
}

if (-not $records) {
    Write-Host "DNS-записи типу '$RecordType' для '$DomainName' не знайдено." -ForegroundColor Yellow
    Write-TkLog "DNS-записи типу '$RecordType' для '$DomainName' не знайдено" -Level WARN
    exit 0
}

# Формування результатів залежно від типу запису
$results = @()

foreach ($record in $records) {
    try {
        $obj = switch ($record.Type) {
            'A' {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = 'A'
                    Value = $record.IPAddress
                    TTL   = $record.TTL
                }
            }
            'AAAA' {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = 'AAAA'
                    Value = $record.IPAddress
                    TTL   = $record.TTL
                }
            }
            'MX' {
                [pscustomobject]@{
                    Name     = $record.Name
                    Type     = 'MX'
                    Value    = $record.NameExchange
                    Priority = $record.Preference
                    TTL      = $record.TTL
                }
            }
            'NS' {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = 'NS'
                    Value = $record.NameHost
                    TTL   = $record.TTL
                }
            }
            'CNAME' {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = 'CNAME'
                    Value = $record.NameHost
                    TTL   = $record.TTL
                }
            }
            'TXT' {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = 'TXT'
                    Value = ($record.Strings -join '; ')
                    TTL   = $record.TTL
                }
            }
            'SOA' {
                [pscustomobject]@{
                    Name          = $record.Name
                    Type          = 'SOA'
                    Value         = $record.PrimaryServer
                    Administrator = $record.NameAdministrator
                    Serial        = $record.SerialNumber
                    TTL           = $record.TTL
                }
            }
            default {
                [pscustomobject]@{
                    Name  = $record.Name
                    Type  = $record.Type.ToString()
                    Value = $record.ToString()
                    TTL   = $record.TTL
                }
            }
        }

        if ($obj) {
            $results += $obj
        }
    } catch {
        Write-TkLog "Помилка обробки DNS-запису: $($_.Exception.Message)" -Level DEBUG
    }
}

if ($results.Count -eq 0) {
    Write-Host "Записи типу '$RecordType' для '$DomainName' не знайдено." -ForegroundColor Yellow
    Write-TkLog "Записи типу '$RecordType' для '$DomainName' не знайдено (після фільтрації)" -Level WARN
    exit 0
}

# Вивід у форматі таблиці з кольоровим оформленням
Write-Host "Знайдено записів: $($results.Count)" -ForegroundColor Green
Write-Host ""
$results | Format-Table -AutoSize

# Підсумок
Write-Host "--- Підсумок ---" -ForegroundColor Cyan
Write-Host "Домен: " -NoNewline
Write-Host "$DomainName" -ForegroundColor Green
Write-Host "Тип запиту: " -NoNewline
Write-Host "$RecordType" -ForegroundColor Green
Write-Host "Знайдено записів: " -NoNewline
Write-Host "$($results.Count)" -ForegroundColor Green

Write-TkLog "DNS-запит для '$DomainName' ($RecordType): знайдено $($results.Count) записів" -Level INFO
