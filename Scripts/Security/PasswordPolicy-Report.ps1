Write-Host "Політика паролів (net accounts):" -ForegroundColor Cyan

$map = @{
    'Force user logoff how long after time expires?' = 'Примусовий вихід при закінченні сесії (хвилин).'
    'Minimum password age (days)'                   = 'Мінімальний вік пароля (днів після зміни).'
    'Maximum password age (days)'                   = 'Максимальний вік пароля.'
    'Minimum password length'                       = 'Мінімальна довжина пароля.'
    'Length of password history maintained'         = 'Історія збережених паролів (кількість).'
    'Lockout threshold'                             = 'Поріг блокування: спроб входу до блокування.'
    'Lockout duration (minutes)'                    = 'Тривалість блокування (хвилин).'
    'Lockout observation window (minutes)'          = 'Вікно спостереження невдалих спроб (хвилин).'
    'Computer role'                                 = 'Роль: WORKSTATION / PRIMARY / BACKUP_DOMAIN_CONTROLLER.'
}

try {
    $output = (& cmd.exe /c 'net accounts' 2>$null) -join "`n"
} catch {
    Write-Error "Не вдалося виконати net accounts: $($_.Exception.Message)"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($output)) {
    Write-Error "Не вдалося отримати вивід net accounts."
    exit 1
}

$lines = $output -split "`r?`n"
foreach ($ln in $lines) {
    if (-not ($ln -match ':')) { continue }
    $kv = $ln -split '\s*:\s*',2
    if ($kv.Count -lt 2) { continue }
    $key = $kv[0].Trim()
    $val = $kv[1].Trim()
    if (-not $key) { continue }
    Write-Host ("{0}: {1}" -f $key,$val)
    if ($map.ContainsKey($key)) {
        Write-Host "  $($map[$key])" -ForegroundColor Gray
    }
}

Write-Host "`nДля детальнішої інформації перегляньте локальні політики (GPO)." -ForegroundColor Gray
