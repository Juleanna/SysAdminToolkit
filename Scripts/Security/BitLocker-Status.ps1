$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора для перевірки BitLocker."
    exit 1
}

if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    Write-Error "Командлет Get-BitLockerVolume недоступний (потрібна функція BitLocker)."
    exit 1
}

try {
    $volumes = Get-BitLockerVolume -ErrorAction Stop
} catch {
    Write-Error "Не вдалося отримати статус BitLocker: $($_.Exception.Message)"
    exit 1
}

if (-not $volumes) {
    Write-Host "Томів не знайдено." -ForegroundColor Yellow
    exit 0
}

$volumes | Select-Object MountPoint,VolumeType,ProtectionStatus,VolumeStatus,EncryptionPercentage,KeyProtector | Format-Table -AutoSize
