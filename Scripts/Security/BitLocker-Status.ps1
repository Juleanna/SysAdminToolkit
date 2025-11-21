if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    Write-Error "Команда Get-BitLockerVolume недоступна (требует BitLocker / модуль BitLocker)."
    exit 1
}

try {
    $volumes = Get-BitLockerVolume -ErrorAction Stop
} catch {
    Write-Error "Не удалось получить статус BitLocker: $($_.Exception.Message)"
    exit 1
}

if (-not $volumes) {
    Write-Host "Томов не найдено." -ForegroundColor Yellow
    exit 0
}

$volumes | Select-Object MountPoint,VolumeType,ProtectionStatus,VolumeStatus,EncryptionPercentage,KeyProtector | Format-Table -AutoSize
