param(
    [switch]$CreateShortcut,
    [switch]$SkipEventLog
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

function Write-Skip {
    param([string]$Message)
    Write-Host "  [--] $Message" -ForegroundColor Yellow
}

# ============================================================
#  Заголовок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SysAdmin Toolkit v5.0 -- Встановлення" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$root = Get-ToolkitRoot

# ============================================================
#  1. Перевірка версії PowerShell
# ============================================================

Write-Step "Перевірка версії PowerShell..."

$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
    Write-Fail "Потрібен PowerShell 5.1 або новіший. Поточна версія: $psVer"
    Write-Host "  Завантажте WMF 5.1: https://aka.ms/wmf5download" -ForegroundColor Yellow
    exit 1
}

Write-OK "PowerShell $psVer"

# ============================================================
#  2. Перевірка прав адміністратора
# ============================================================

Write-Step "Перевірка прав адміністратора..."

$isAdmin = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Fail "Потрібні права адміністратора для повної установки."
    Write-Host "  Запустіть PowerShell від імені адміністратора та повторіть." -ForegroundColor Yellow
    exit 1
}

Write-OK "Права адміністратора підтверджено"

# ============================================================
#  3. Створення директорій
# ============================================================

Write-Step "Створення робочих директорій..."

$dirs = @(
    (Join-Path $root "Logs"),
    (Join-Path $root "Reports")
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Створено: $dir"
    } else {
        Write-Skip "Вже існує: $dir"
    }
}

# ============================================================
#  4. Валідація конфігураційних файлів
# ============================================================

Write-Step "Перевірка конфігураційних файлів..."

$configFiles = @(
    @{ Path = "Config\ToolkitConfig.json"; Required = $true },
    @{ Path = "Config\Telegram.json";      Required = $true },
    @{ Path = "Config\Hosts.json";         Required = $true },
    @{ Path = "Config\Roles.json";         Required = $false }
)

$allConfigsOk = $true

foreach ($cf in $configFiles) {
    $fullPath = Join-Path $root $cf.Path
    if (Test-Path $fullPath) {
        try {
            $null = Get-Content $fullPath -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            Write-OK "Валідний JSON: $($cf.Path)"
        } catch {
            Write-Fail "Невалідний JSON: $($cf.Path) -- $($_.Exception.Message)"
            $allConfigsOk = $false
        }
    } else {
        if ($cf.Required) {
            Write-Fail "Не знайдено: $($cf.Path)"
            $allConfigsOk = $false
        } else {
            Write-Skip "Не знайдено (опційний): $($cf.Path)"
        }
    }
}

if (-not $allConfigsOk) {
    Write-Host ""
    Write-Host "  Увага: деякі конфігураційні файли відсутні або невалідні." -ForegroundColor Yellow
    Write-Host "  Тулкіт використовуватиме значення за замовчуванням." -ForegroundColor Yellow
}

# ============================================================
#  5. Перевірка модуля ToolkitCommon
# ============================================================

Write-Step "Перевірка модуля ToolkitCommon.psm1..."

$modulePath = Join-Path $root "Scripts\Utils\ToolkitCommon.psm1"
if (Test-Path $modulePath) {
    Write-OK "Модуль знайдено: $modulePath"
} else {
    Write-Fail "Модуль не знайдено: $modulePath"
    Write-Host "  Установка неможлива без ToolkitCommon.psm1" -ForegroundColor Red
    exit 1
}

# ============================================================
#  6. Реєстрація джерела Windows Event Log
# ============================================================

if (-not $SkipEventLog) {
    Write-Step "Реєстрація джерела Event Log 'SysAdminToolkit'..."

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists("SysAdminToolkit")) {
            [System.Diagnostics.EventLog]::CreateEventSource("SysAdminToolkit", "Application")
            Write-OK "Джерело 'SysAdminToolkit' зареєстровано в Application Event Log"
        } else {
            Write-Skip "Джерело 'SysAdminToolkit' вже зареєстровано"
        }
    } catch {
        Write-Fail "Не вдалося зареєструвати Event Log: $($_.Exception.Message)"
        Write-Host "  Це не критично -- логування працюватиме через файл Logs/Toolkit.log" -ForegroundColor Yellow
    }
} else {
    Write-Skip "Реєстрація Event Log пропущена (-SkipEventLog)"
}

# ============================================================
#  7. Створення ярлика на робочому столі (опційно)
# ============================================================

if ($CreateShortcut) {
    Write-Step "Створення ярлика на робочому столі..."

    try {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktop "SysAdmin Toolkit.lnk"
        $guiPath = Join-Path $root "SysAdminToolkit.GUI.ps1"

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy RemoteSigned -File `"$guiPath`""
        $shortcut.WorkingDirectory = $root
        $shortcut.Description = "SysAdmin Toolkit v5.0"
        $shortcut.IconLocation = "shell32.dll,21"
        $shortcut.Save()

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

        Write-OK "Ярлик створено: $shortcutPath"
    } catch {
        Write-Fail "Не вдалося створити ярлик: $($_.Exception.Message)"
    }
} else {
    Write-Skip "Ярлик не створюється (використовуйте -CreateShortcut)"
}

# ============================================================
#  8. Перевірка Execution Policy
# ============================================================

Write-Step "Перевірка Execution Policy..."

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Host "  [УВАГА] Поточна Execution Policy: $policy" -ForegroundColor Yellow
    Write-Host "  Рекомендується встановити RemoteSigned:" -ForegroundColor Yellow
    Write-Host "    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor White
} else {
    Write-OK "Execution Policy: $policy"
}

# ============================================================
#  Підсумок
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Встановлення завершено успішно!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Запуск GUI:" -ForegroundColor White
Write-Host "    cd $root" -ForegroundColor Gray
Write-Host "    .\SysAdminToolkit.GUI.ps1" -ForegroundColor Gray
Write-Host ""

Write-TkLog "Install.ps1: встановлення завершено на $env:COMPUTERNAME" -Level INFO
