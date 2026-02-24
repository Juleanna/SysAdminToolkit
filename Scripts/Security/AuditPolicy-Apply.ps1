param(
    [ValidateSet('Status','Apply')]
    [string]$Mode = 'Status'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($Mode -eq 'Apply' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора для застосування аудит-політик."
    exit 1
}

function Show-Audit {
    try {
        auditpol /get /category:* | ForEach-Object { $_ }
    } catch {
        Write-Error "Не вдалося отримати аудит-політики: $($_.Exception.Message)"
    }
}

if ($Mode -eq 'Status') {
    Write-Host "Поточні аудит-політики:" -ForegroundColor Cyan
    Show-Audit
    exit 0
}

$recommended = @(
    'Logon', 'Logoff', 'Account Lockout',
    'User Account Management','Security Group Management',
    'Credential Validation','Privilege Use','Process Creation'
)

foreach ($sub in $recommended) {
    try {
        auditpol /set /subcategory:"$sub" /success:enable /failure:enable | Out-Null
    } catch {
        Write-Warning "Не вдалося увімкнути ${sub}: $($_.Exception.Message)"
    }
}

Write-Host "Рекомендовані аудит-політики увімкнено (успіх+помилка)." -ForegroundColor Green
Write-Host "Поточні налаштування:" -ForegroundColor Cyan
Show-Audit
