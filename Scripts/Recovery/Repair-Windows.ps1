$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора для SFC/DISM."
    exit 1
}

function Invoke-WithProgress {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [string]$Activity,
        [int]$StartPercent = 0,
        [int]$EndPercent = 100,
        [int]$TickSeconds = 5
    )

    $tmp = New-TemporaryFile
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $tmp.FullName -NoNewWindow -PassThru

    $percent = $StartPercent
    while (-not $p.HasExited) {
        $percent = [math]::Min($EndPercent - 1, $percent + 1)
        Write-Output ("PROGRESS: {0}" -f $percent)
        Start-Sleep -Seconds $TickSeconds
    }

    Write-Output ("PROGRESS: {0}" -f $EndPercent)

    if ($p.ExitCode -ne 0) {
        Write-Warning "$Activity завершено з кодом: $($p.ExitCode)"
    }

    Get-Content $tmp.FullName | ForEach-Object { Write-Output $_ }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Output "Запускаю перевірку системних файлів (SFC)..."
Invoke-WithProgress -FilePath "sfc.exe" -Arguments "/scannow" -Activity "SFC /scannow" -StartPercent 0 -EndPercent 50 -TickSeconds 3

Write-Output "`nЗапускаю відновлення образу (DISM)..."
Invoke-WithProgress -FilePath "DISM.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth" -Activity "DISM /RestoreHealth" -StartPercent 50 -EndPercent 100 -TickSeconds 5
