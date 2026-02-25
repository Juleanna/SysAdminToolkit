param(
    [ValidateSet('List','Create','DeleteOld')]
    [string]$Mode = 'List',
    [string]$Description = "SysAdminToolkit Checkpoint",
    [int]$KeepDays = 30
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Точки відновлення системи" -ForegroundColor Cyan
Write-Host "  Режим: $Mode" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-TkLog "Manage-RestorePoints: Старт, режим=$Mode" -Level INFO

switch ($Mode) {
    'List' {
        Write-Host "`n--- Існуючі точки відновлення ---" -ForegroundColor Cyan
        try {
            $points = Get-ComputerRestorePoint -ErrorAction Stop
            if ($points.Count -eq 0) {
                Write-Host "  [УВАГА] Точок відновлення не знайдено." -ForegroundColor Yellow
            } else {
                foreach ($p in $points) {
                    $created = [System.Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime)
                    $age = [math]::Round(((Get-Date) - $created).TotalDays, 1)
                    $color = if ($age -gt 30) { 'Yellow' } else { 'Gray' }
                    Write-Host "  [$($p.SequenceNumber)] $($p.Description)" -ForegroundColor $color
                    Write-Host "       Створено: $($created.ToString('yyyy-MM-dd HH:mm')) ($age днів тому)" -ForegroundColor $color
                }
                Write-Host "`n  Всього: $($points.Count) точок" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Можливо, відновлення системи вимкнено." -ForegroundColor Yellow
            Write-TkLog "Помилка отримання точок відновлення: $($_.Exception.Message)" -Level ERROR
        }
    }

    'Create' {
        Assert-Administrator
        Write-Host "`n--- Створення точки відновлення ---" -ForegroundColor Cyan
        Write-Host "  Опис: $Description" -ForegroundColor Gray

        # Перевірка чи ввімкнено System Restore
        try {
            $srStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -ErrorAction SilentlyContinue
            if ($srStatus.RPSessionInterval -eq 0 -and $srStatus.DisableSR -eq 1) {
                Write-Host "  [ПОМИЛКА] Відновлення системи вимкнено. Увімкніть його у налаштуваннях." -ForegroundColor Red
                Write-TkLog "System Restore вимкнено" -Level ERROR
                exit 1
            }
        } catch {}

        # Перевірка частоти створення
        try {
            $freq = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue
            if ($null -eq $freq) {
                Write-Host "  [УВАГА] Windows обмежує створення точок до 1 на 24 години." -ForegroundColor Yellow
            }
        } catch {}

        Write-Host "PROGRESS: 30"

        try {
            Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Host "PROGRESS: 90"

            # Перевірка що точка створена
            $latest = Get-ComputerRestorePoint | Select-Object -Last 1
            if ($latest -and $latest.Description -eq $Description) {
                Write-Host "  [OK] Точку відновлення успішно створено." -ForegroundColor Green
                $created = [System.Management.ManagementDateTimeConverter]::ToDateTime($latest.CreationTime)
                Write-Host "  Номер: $($latest.SequenceNumber)" -ForegroundColor Gray
                Write-Host "  Час: $($created.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
                Write-TkLog "Точку відновлення створено: #$($latest.SequenceNumber) '$Description'" -Level INFO
            } else {
                Write-Host "  [OK] Команда виконана (можливо, Windows пропустила через обмеження частоти)." -ForegroundColor Yellow
                Write-TkLog "Checkpoint-Computer виконано, але точку не підтверджено" -Level WARN
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Помилка створення точки відновлення: $($_.Exception.Message)" -Level ERROR
        }
    }

    'DeleteOld' {
        Assert-Administrator
        Write-Host "`n--- Видалення старих тіньових копій (>$KeepDays днів) ---" -ForegroundColor Cyan

        try {
            $shadows = & vssadmin list shadows 2>&1
            $shadowBlocks = @()
            $currentBlock = @{}

            foreach ($line in $shadows) {
                if ($line -match 'Shadow Copy ID:\s*(\{[^}]+\})') {
                    if ($currentBlock.ID) { $shadowBlocks += [PSCustomObject]$currentBlock }
                    $currentBlock = @{ ID = $Matches[1] }
                }
                if ($line -match 'creation date:\s*(.+)$' -or $line -match 'Original Volume:.*\((\w:)\)') {
                    if ($Matches[1] -and -not $currentBlock.Date) {
                        try { $currentBlock.Date = [datetime]::Parse($Matches[1].Trim()) } catch {}
                    }
                }
            }
            if ($currentBlock.ID) { $shadowBlocks += [PSCustomObject]$currentBlock }

            $toDelete = @()
            $cutoff = (Get-Date).AddDays(-$KeepDays)
            foreach ($sb in $shadowBlocks) {
                if ($sb.Date -and $sb.Date -lt $cutoff) {
                    $toDelete += $sb
                }
            }

            if ($toDelete.Count -eq 0) {
                Write-Host "  Немає тіньових копій старших за $KeepDays днів." -ForegroundColor Green
            } else {
                Write-Host "  Знайдено $($toDelete.Count) старих тіньових копій" -ForegroundColor Yellow
                $deleted = 0
                foreach ($sd in $toDelete) {
                    try {
                        $age = [math]::Round(((Get-Date) - $sd.Date).TotalDays, 0)
                        & vssadmin delete shadows /shadow=$($sd.ID) /quiet 2>&1 | Out-Null
                        Write-Host "  [OK] Видалено: $($sd.ID) ($age днів)" -ForegroundColor Green
                        $deleted++
                    } catch {
                        Write-Host "  [ПОМИЛКА] $($sd.ID): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host "`n  Видалено: $deleted з $($toDelete.Count)" -ForegroundColor $(if ($deleted -eq $toDelete.Count) { 'Green' } else { 'Yellow' })
                Write-TkLog "Видалено $deleted старих тіньових копій (>$KeepDays днів)" -Level INFO
            }
        } catch {
            Write-Host "  [ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Помилка видалення тіньових копій: $($_.Exception.Message)" -Level ERROR
        }
    }
}

Write-Host "PROGRESS: 100"
Write-Host "`n[Завершено] Точки відновлення ($Mode)" -ForegroundColor Cyan
