param(
    [ValidateSet('Status','Scan','UpdateDefender')]
    [string]$Action = 'Status'
)

if ($Action -ne 'Status') {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Потрібні права адміністратора."
        exit 1
    }
}

function Show-Info {
    $wua = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $usocli = Get-Command UsoClient.exe -ErrorAction SilentlyContinue
    $hotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5
    $mp = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    $mpStatus = $null
    if ($mp -and $mp.Status -eq 'Running') {
        try {
            $mpStatus = Get-MpComputerStatus | Select-Object AMEngineVersion,AntivirusEnabled,AntispywareEnabled,RealTimeProtectionEnabled,QuickScanEndTime
        } catch {}
    }
    $wuaStatus = if ($wua) { $wua.Status } else { 'Не знайдено' }
    Write-Host "Статус wuauserv: $wuaStatus" -ForegroundColor Cyan
    if ($usocli) { Write-Host "UsoClient доступний (scan/install)." }
    Write-Host "Останні оновлення:" -ForegroundColor Cyan
    if ($hotfix) {
        $hotfix | Select-Object InstalledOn,Description,HotFixID | Format-Table -AutoSize
    } else {
        Write-Host "  Немає даних про оновлення." -ForegroundColor Yellow
    }
    if ($mpStatus) {
        Write-Host "Defender:" -ForegroundColor Cyan
        $mpStatus | Format-List
    } else {
        Write-Host "Defender статус недоступний або служба не запущена." -ForegroundColor Yellow
    }
}

switch ($Action) {
    'Status' {
        Show-Info
    }
    'Scan' {
        try {
            Start-Service -Name wuauserv -ErrorAction Stop
        } catch { Write-Warning "wuauserv: $($_.Exception.Message)" }
        $uso = Get-Command UsoClient.exe -ErrorAction SilentlyContinue
        if ($uso) {
            Write-Host "Запуск Windows Update сканування (UsoClient StartScan)..." -ForegroundColor Cyan
            & $uso.Source StartScan | Out-Null
        } else {
            Write-Warning "UsoClient не знайдено; спробуйте перевірити оновлення вручну."
        }
        Show-Info
    }
    'UpdateDefender' {
        try {
            Start-Service -Name WinDefend -ErrorAction Stop
            Update-MpSignature -ErrorAction Stop | Out-Null
            Write-Host "Сигнатури Defender оновлено." -ForegroundColor Green
        } catch {
            Write-Error "Не вдалося оновити Defender: $($_.Exception.Message)"
        }
        Show-Info
    }
}
