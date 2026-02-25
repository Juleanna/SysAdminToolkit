param(
    [ValidateSet('Git', 'Zip')]
    [string]$Source = 'Git',

    [string]$ZipUrl = ''
)

Import-Module "$PSScriptRoot\Scripts\Utils\ToolkitCommon.psm1" -Force

$ErrorActionPreference = 'Stop'

# ============================================================
#  Кольоровий вивід
# ============================================================

function Write-Step {
    param([string]$Message)
    Write-Host "  [*] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [ПОМИЛКА] $Message" -ForegroundColor Red
}

# ============================================================
#  Заголовок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SysAdmin Toolkit -- Оновлення ($Source)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$root = Get-ToolkitRoot
$configDir = Join-Path $root "Config"
$backupDir = Join-Path $root "Config_Backup"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "${backupDir}_${timestamp}"

# ============================================================
#  1. Резервне копіювання Config/
# ============================================================

Write-Step "Резервне копіювання Config/..."

if (Test-Path $configDir) {
    try {
        Copy-Item -Path $configDir -Destination $backupPath -Recurse -Force
        Write-OK "Конфігурацію збережено: $backupPath"
        Write-TkLog "Update-Toolkit: бекап Config -> $backupPath" -Level INFO
    } catch {
        Write-Fail "Не вдалося зберегти конфігурацію: $($_.Exception.Message)"
        Write-TkLog "Update-Toolkit: помилка бекапу Config -- $($_.Exception.Message)" -Level ERROR
        exit 1
    }
} else {
    Write-Host "  [--] Config/ не знайдено, бекап не потрібен" -ForegroundColor Yellow
}

# ============================================================
#  2. Оновлення
# ============================================================

switch ($Source) {

    'Git' {
        Write-Step "Оновлення через Git..."

        # Перевірка наявності git
        $gitPath = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitPath) {
            Write-Fail "Git не знайдено в PATH. Встановіть Git або використовуйте -Source Zip"
            Write-TkLog "Update-Toolkit: git не знайдено" -Level ERROR
            exit 1
        }

        # Перевірка чи це git-репозиторій
        $gitDir = Join-Path $root ".git"
        if (-not (Test-Path $gitDir)) {
            Write-Fail "Каталог $root не є git-репозиторієм. Використовуйте -Source Zip"
            Write-TkLog "Update-Toolkit: не git-репозиторій" -Level ERROR
            exit 1
        }

        try {
            Push-Location $root

            # Зберігаємо локальні зміни
            Write-Step "Перевірка локальних змін..."
            $status = & git status --porcelain 2>&1
            if ($status) {
                Write-Host "  [!] Знайдено локальні зміни, зберігаємо через git stash..." -ForegroundColor Yellow
                & git stash push -m "toolkit-update-$timestamp" 2>&1 | Out-Null
                Write-OK "Локальні зміни збережено (git stash)"
            }

            # Оновлення
            Write-Step "Виконання git pull..."
            $pullResult = & git pull --ff-only 2>&1
            $pullExitCode = $LASTEXITCODE

            if ($pullExitCode -eq 0) {
                Write-OK "Git pull завершено успішно"
                $pullResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
            } else {
                Write-Fail "Git pull завершився з помилкою (exit code: $pullExitCode)"
                $pullResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                Write-TkLog "Update-Toolkit: git pull помилка -- $pullResult" -Level ERROR
            }

            Pop-Location
        } catch {
            Pop-Location
            Write-Fail "Помилка Git: $($_.Exception.Message)"
            Write-TkLog "Update-Toolkit: помилка git -- $($_.Exception.Message)" -Level ERROR
            exit 1
        }
    }

    'Zip' {
        Write-Step "Оновлення з ZIP-архіву..."

        if ([string]::IsNullOrWhiteSpace($ZipUrl)) {
            Write-Fail "Вкажіть -ZipUrl з URL або локальним шляхом до ZIP-архіву"
            exit 1
        }

        $tempZip = Join-Path $env:TEMP "SysAdminToolkit_Update_${timestamp}.zip"
        $tempExtract = Join-Path $env:TEMP "SysAdminToolkit_Update_${timestamp}"

        try {
            # Завантаження або копіювання ZIP
            if ($ZipUrl -match '^https?://') {
                Write-Step "Завантаження ZIP з $ZipUrl..."
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri $ZipUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
                    Write-OK "ZIP завантажено: $tempZip"
                } catch {
                    Write-Fail "Не вдалося завантажити ZIP: $($_.Exception.Message)"
                    Write-TkLog "Update-Toolkit: помилка завантаження ZIP -- $($_.Exception.Message)" -Level ERROR
                    exit 1
                }
            } else {
                # Локальний файл
                if (-not (Test-Path $ZipUrl)) {
                    Write-Fail "Файл не знайдено: $ZipUrl"
                    exit 1
                }
                Copy-Item -Path $ZipUrl -Destination $tempZip -Force
                Write-OK "ZIP скопійовано: $tempZip"
            }

            # Розпакування
            Write-Step "Розпакування архіву..."
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
            Write-OK "Розпаковано: $tempExtract"

            # Пошук кореневої папки в архіві
            $extracted = Get-ChildItem $tempExtract
            $sourceDir = $tempExtract
            if ($extracted.Count -eq 1 -and $extracted[0].PSIsContainer) {
                $sourceDir = $extracted[0].FullName
            }

            # Копіювання файлів (без перезапису Config/)
            Write-Step "Копіювання оновлених файлів..."

            $items = Get-ChildItem $sourceDir -Force
            foreach ($item in $items) {
                $destPath = Join-Path $root $item.Name
                if ($item.Name -eq "Config") {
                    Write-Host "  [--] Пропускаємо Config/ (збережено бекап)" -ForegroundColor Yellow
                    continue
                }
                Copy-Item -Path $item.FullName -Destination $destPath -Recurse -Force
                Write-Host "    Оновлено: $($item.Name)" -ForegroundColor Gray
            }

            Write-OK "Файли оновлено"

        } finally {
            # Очищення тимчасових файлів
            if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ============================================================
#  3. Відновлення конфігурації
# ============================================================

Write-Step "Перевірка конфігурації після оновлення..."

if (Test-Path $backupPath) {
    # Перевіряємо чи Config/ існує після оновлення
    if (-not (Test-Path $configDir)) {
        Write-Host "  [!] Config/ зник після оновлення, відновлюємо з бекапу..." -ForegroundColor Yellow
        Copy-Item -Path $backupPath -Destination $configDir -Recurse -Force
        Write-OK "Конфігурацію відновлено з бекапу"
    } else {
        # Перевіряємо наявність ключових файлів
        $keyFiles = @("ToolkitConfig.json", "Telegram.json", "Hosts.json")
        foreach ($kf in $keyFiles) {
            $cfgFile = Join-Path $configDir $kf
            $bkpFile = Join-Path $backupPath $kf
            if (-not (Test-Path $cfgFile) -and (Test-Path $bkpFile)) {
                Copy-Item -Path $bkpFile -Destination $cfgFile -Force
                Write-OK "Відновлено з бекапу: $kf"
            }
        }
    }
}

# ============================================================
#  Підсумок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Оновлення завершено!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Бекап конфігурації: $backupPath" -ForegroundColor Gray
Write-Host "  Перезапустіть GUI для застосування змін." -ForegroundColor White
Write-Host ""

Write-TkLog "Update-Toolkit: оновлення завершено (Source=$Source)" -Level INFO
