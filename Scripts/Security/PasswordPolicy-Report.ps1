Write-Host "Политика паролей (net accounts):" -ForegroundColor Cyan

$proc = Start-Process -FilePath cmd.exe -ArgumentList '/c','net accounts' -NoNewWindow -RedirectStandardOutput -PassThru
$proc.WaitForExit()
$output = $proc.StandardOutput.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($output)) {
    Write-Error "Не удалось получить вывод net accounts."
    exit 1
}

$output -split "`r?`n" | ForEach-Object {
    if ($_ -match '\s{2,}') {
        $line = ($_ -replace '\s{2,}', ': ').Trim()
        Write-Host $line
    }
}

Write-Host "`nЕсли машина в домене, значения берутся из доменной политики." -ForegroundColor Gray
