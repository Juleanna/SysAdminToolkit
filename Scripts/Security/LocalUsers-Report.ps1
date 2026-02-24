param(
    [switch]$AdminsOnly
)

$canLocalUser = Get-Command Get-LocalUser -ErrorAction SilentlyContinue

if ($canLocalUser) {
    try {
        $users = Get-LocalUser -ErrorAction Stop
    } catch {
        Write-Error "Не вдалося отримати локальних користувачів: $($_.Exception.Message)"
        exit 1
    }

    $admins = @{}
    try {
        Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
            ForEach-Object { $admins[$_.Name] = $true }
    } catch {}

    if ($AdminsOnly) {
        $users = $users | Where-Object { $admins.ContainsKey($_.Name) }
    }

    if (-not $users) {
        Write-Host "Користувачів не знайдено." -ForegroundColor Yellow
        exit 0
    }

    $users | Select-Object Name,Enabled,@{n='Admin';e={ $admins.ContainsKey($_.Name) }},LastLogon,PasswordExpires |
        Format-Table -AutoSize
    exit 0
}

# Fallback через net user, якщо модуль LocalAccounts недоступний
Write-Warning "Модуль LocalAccounts недоступний, використовую net user."
try {
    $raw = net user
} catch {
    Write-Error "Не вдалося виконати net user: $($_.Exception.Message)"
    exit 1
}

$lines = $raw -split "`r?`n"
$userList = @()
$collect = $false
foreach ($ln in $lines) {
    if ($ln -match '^The command completed successfully') { break }
    if ($ln -match '^\\') { continue }
    if ($ln -match '^User accounts') { $collect = $true; continue }
    if (-not $collect) { continue }
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    $parts = $ln -split '\s+' | Where-Object { $_ }
    $userList += $parts
}

if ($AdminsOnly) {
    try {
        $adm = net localgroup Administrators
        $admLines = $adm -split "`r?`n"
        $admNames = $admLines | Where-Object { $_ -and $_ -notmatch 'command completed successfully' -and $_ -notmatch '^Alias' -and $_ -notmatch '^Comment' -and $_ -notmatch '^Members' -and $_ -notmatch '^---' }
        $userList = $userList | Where-Object { $admNames -contains $_ }
    } catch {}
}

if (-not $userList) {
    Write-Host "Користувачів не знайдено." -ForegroundColor Yellow
    exit 0
}

$userList | ForEach-Object { Write-Host $_ }
