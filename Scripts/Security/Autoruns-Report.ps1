param(
    [string]$DisableServiceName,
    [string]$DisableTaskPath
)

Write-Host "Автозапуск та заплановані завдання:" -ForegroundColor Cyan

$runKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($key in $runKeys) {
    if (-not (Test-Path $key)) { continue }
    Write-Host "[Run] $key" -ForegroundColor Yellow
    try {
        $props = Get-ItemProperty -Path $key | Select-Object *
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
            Write-Host "  $($p.Name) = $($p.Value)"
        }
    } catch {
        Write-Warning "Не вдалося прочитати ${key}: $($_.Exception.Message)"
    }
}

Write-Host "`nЗаплановані завдання:" -ForegroundColor Yellow
try {
    Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.State -ne 'Disabled' } |
        Select-Object TaskName,TaskPath,State | Format-Table -AutoSize
} catch {
    Write-Warning "Не вдалося отримати заплановані завдання: $($_.Exception.Message)"
}

Write-Host "`nСервіси (автозапуск):" -ForegroundColor Yellow
try {
    Get-Service | Where-Object { $_.StartType -eq 'Automatic' } | Select-Object Name,DisplayName,Status | Format-Table -AutoSize
} catch {
    Write-Warning "Не вдалося отримати сервіси: $($_.Exception.Message)"
}

if ($DisableServiceName) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Потрібні права адміністратора для зміни сервісів."
        exit 1
    }
    try {
        Set-Service -Name $DisableServiceName -StartupType Manual -ErrorAction Stop
        Write-Host "Сервіс ${DisableServiceName} переведено в Manual." -ForegroundColor Green
    } catch {
        Write-Error "Не вдалося змінити сервіс ${DisableServiceName}: $($_.Exception.Message)"
    }
}

if ($DisableTaskPath) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Потрібні права адміністратора для вимкнення завдань."
        exit 1
    }
    try {
        Disable-ScheduledTask -TaskName (Split-Path $DisableTaskPath -Leaf) -TaskPath (Split-Path $DisableTaskPath -Parent) -ErrorAction Stop | Out-Null
        Write-Host "Завдання ${DisableTaskPath} вимкнено." -ForegroundColor Green
    } catch {
        Write-Error "Не вдалося вимкнути завдання ${DisableTaskPath}: $($_.Exception.Message)"
    }
}
