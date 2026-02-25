# CLAUDE.md -- Інструкції для AI-розробника

Цей файл містить контекст та правила для роботи з кодовою базою SysAdminToolkit.

## Архітектура

```
SysAdminToolkit/
├── SysAdminToolkit.GUI.ps1       # WPF GUI (XAML dark theme, Catppuccin Mocha)
├── Scripts/
│   ├── <Category>/               # 18 категорій зі скриптами
│   └── Utils/
│       └── ToolkitCommon.psm1    # Спільний модуль (19 експортованих функцій)
├── Config/
│   ├── ToolkitConfig.json        # Загальна конфігурація тулкіту
│   ├── Telegram.json             # Конфіг Telegram-бота
│   ├── Hosts.json                # Керовані хости
│   └── Roles.json                # RBAC-ролі
├── Logs/                         # Лог-файли з авторотацією
├── Reports/                      # Згенеровані HTML/CSV/JSON звіти
└── Tests/                        # Pester-тести
```

### Потік виконання

1. Користувач запускає `SysAdminToolkit.GUI.ps1`
2. GUI завантажує `ToolkitCommon.psm1` та читає `ToolkitConfig.json`
3. Масив `$global:Actions` визначає всі операції (Category, Name, Script, Desc)
4. Скрипт запускається через `Start-Job` у фоновому процесі
5. `DispatcherTimer` кожні 500мс збирає вивід Job та показує у RichTextBox
6. Результат записується в історію та лог

## Конвенції коду

### Структура скрипту

Кожен `.ps1` скрипт ОБОВ'ЯЗКОВО починається з `param()` блоку ПЕРЕД `Import-Module`:

```powershell
param(
    [string]$ComputerName,
    [int]$TimeoutSec = 30
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

# ... решта коду
```

Це критично, тому що GUI передає параметри через масив аргументів.

### Мова

- Весь UI-текст, коментарі, повідомлення Write-Host, описи -- **українською**
- Імена функцій, параметрів, змінних -- **англійською** (PowerShell Verb-Noun)
- Коментарі у коді -- українською

### Логування

Використовуй `Write-TkLog` для логування у файл:

```powershell
Write-TkLog "Починаємо сканування підмережі" -Level INFO
Write-TkLog "Хост $ComputerName недоступний" -Level WARN
Write-TkLog "Критична помилка: $($_.Exception.Message)" -Level ERROR
```

Рівні: `DEBUG`, `INFO`, `WARN`, `ERROR`. Логи зберігаються у `Logs/Toolkit.log`.

### Обробка помилок

Завжди обгортай критичні операції у `try/catch`:

```powershell
try {
    # операція
} catch {
    Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
    Write-TkLog "Опис помилки: $($_.Exception.Message)" -Level ERROR
    exit 1
}
```

### Кодування файлів

Усі `.ps1` та `.psm1` файли зберігаються у **UTF-8 with BOM** для коректного відображення кирилиці.

### Кольоровий вивід

Використовуй `Write-Host` з кольорами для інтерактивного виводу:

```powershell
Write-Host "Заголовок операції" -ForegroundColor Cyan
Write-Host "[OK] Успішно завершено" -ForegroundColor Green
Write-Host "[УВАГА] Попередження" -ForegroundColor Yellow
Write-Host "[ПОМИЛКА] Щось пішло не так" -ForegroundColor Red
Write-Host "Інформаційний текст" -ForegroundColor Gray
```

GUI автоматично розпізнає ключові слова та фарбує рядки:
- `помилка/error/fail` -> червоний (#f38ba8)
- `попередження/warning/увага` -> оранжевий (#fab387)
- `успішно/success/done/ok/завершено` -> зелений (#a6e3a1)

## Модуль ToolkitCommon.psm1 -- 19 експортованих функцій

### Конфігурація та шляхи
| Функція | Опис |
|---|---|
| `Get-ToolkitRoot` | Повертає кореневу папку тулкіту |
| `Get-ToolkitConfig` | Завантажує `ToolkitConfig.json` з дефолтами |
| `Get-TkHostsList` | Список хостів з `Hosts.json` |

### Параметри
| Функція | Опис |
|---|---|
| `ConvertFrom-ParamString` | Перетворює `"Key=Val;Key2=Val2"` у Hashtable |

### Перевірки
| Функція | Опис |
|---|---|
| `Assert-Administrator` | Перевірка прав адміністратора (exit 1 якщо немає) |
| `Test-ComputerOnline` | Пінг комп'ютера з таймаутом |
| `Test-TkPrerequisite` | Комплексна перевірка передумов (Admin, Modules, PS version, Online) |

### Логування та сповіщення
| Функція | Опис |
|---|---|
| `Write-TkLog` | Запис у лог-файл з ротацією |
| `Write-TkEventLog` | Запис у Windows Event Log (джерело SysAdminToolkit) |
| `Show-TkNotification` | WPF balloon-сповіщення у системному треї |

### Мережа та виконання
| Функція | Опис |
|---|---|
| `Invoke-WithRetry` | ScriptBlock з автоматичними повторними спробами |
| `Invoke-TkRemote` | Обгортка `Invoke-Command` з retry та логуванням |

### Звіти та дані
| Функція | Опис |
|---|---|
| `Export-TkReport` | Експорт у CSV/JSON/HTML |
| `ConvertTo-TkResult` | Стандартний об'єкт результату |
| `ConvertTo-TkHtmlDashboard` | Зведений HTML-дашборд з секціями |

### Email та облікові дані
| Функція | Опис |
|---|---|
| `Send-TkEmail` | Відправка email через SMTP |
| `Get-TkCredential` | DPAPI-збереження облікових даних |

### RBAC
| Функція | Опис |
|---|---|
| `Get-TkUserRole` | Поточна роль користувача |
| `Test-TkRoleAccess` | Перевірка доступу до категорії |

## Як додати новий скрипт

1. Створи файл у відповідній категорії: `Scripts/<Category>/<Verb-Noun>.ps1`
2. Почни з `param()` блоку, потім `Import-Module`
3. Додай запис до масиву `$global:Actions` у `SysAdminToolkit.GUI.ps1`:

```powershell
[PSCustomObject]@{
    Category = "Назва категорії українською"
    Name     = "Назва операції українською"
    Script   = "Category\Verb-Noun.ps1"      # відносний шлях від Scripts/
    Desc     = "Опис що робить скрипт (параметри формат: ParamName=значення)"
}
```

4. Якщо скрипт приймає параметри, вкажи їх у `Desc` у дужках

## Як додати дію до GUI

Додай `[PSCustomObject]` до масиву `$global:Actions` у `SysAdminToolkit.GUI.ps1` у відповідну секцію (коментар `# ===== Назва =====`):

```powershell
# ===== Моніторинг =====
[PSCustomObject]@{
    Category = "Моніторинг"
    Name     = "Нова дія"
    Script   = "Monitoring\New-Action.ps1"
    Desc     = "Опис нової дії"
}
```

GUI автоматично підхопить новий запис -- перезапуск не потрібен якщо масив оновлено.

## Довідка по конфігурації

### ToolkitConfig.json
```json
{
  "CompanyName": "Dafna",
  "DefaultBackupPath": "D:/Backups",
  "Subnet": "192.168.1.",
  "LogLevel": "INFO",              // DEBUG, INFO, WARN, ERROR
  "MaxLogSizeMB": 10,
  "BackupRetentionDays": 30,
  "RemoteTimeoutSec": 30,
  "RetryCount": 3,
  "DiskSpaceWarningPercent": 80,
  "DiskSpaceCriticalPercent": 95,
  "CertExpiryWarnDays": 30,
  "CriticalServices": ["Spooler", "wuauserv", "WinDefend", "EventLog", "Dnscache"]
}
```

### Telegram.json
```json
{
  "BotToken": "",                   // або через $env:SYSADMINTK_BOTTOKEN
  "ChatID": "",
  "Enabled": false
}
```

### Hosts.json
```json
{
  "Hosts": [
    { "Name": "PC-01", "IP": "192.168.1.10", "Role": "Workstation", "Description": "" }
  ]
}
```

### Roles.json
```json
{
  "Roles": {
    "Admin":    { "AllowedCategories": ["*"] },
    "Operator": { "AllowedCategories": ["monitoring", "inventory", ...] },
    "Auditor":  { "AllowedCategories": ["inventory", "monitoring", "reports", "security"] }
  },
  "DefaultRole": "Admin"
}
```

## Іменування

- Скрипти: `Verb-Noun.ps1` (PowerShell approved verbs)
- Модуль: `ToolkitCommon.psm1` (єдиний модуль)
- Функції модуля: `Verb-TkNoun` або `Verb-ToolkitNoun` (префікс `Tk`)
- Параметри: PascalCase (`$ComputerName`, `$OutputPath`)
- Конфіг-файли: PascalCase JSON-ключі (`CompanyName`, `LogLevel`)

## ЗАБОРОНИ (DO NOTs)

1. **НЕ використовуй `$args`** -- завжди оголошуй параметри через `param()`. Скрипти викликаються через GUI з іменованими параметрами.

2. **НЕ додавай параметр `-Form` або `-Window`** до скриптів. GUI сам керує вікном. Скрипти працюють у Job і не мають доступу до WPF-елементів.

3. **НЕ пропускай перевірку адміністратора** для скриптів, що змінюють систему. Використовуй:
   ```powershell
   Assert-Administrator
   # або
   Test-TkPrerequisite -RequireAdmin
   ```

4. **НЕ використовуй `Write-Output` для UI-повідомлень** -- використовуй `Write-Host` з кольорами. `Write-Output` йде у pipeline і може зламати логіку.

5. **НЕ зберігай секрети у коді** -- Telegram-токен через `$env:SYSADMINTK_BOTTOKEN`, облікові дані через `Get-TkCredential`.

6. **НЕ використовуй відносні шляхи** для Import-Module -- завжди:
   ```powershell
   Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force
   ```

7. **НЕ видаляй та не переміщуй `ToolkitCommon.psm1`** -- від нього залежать усі скрипти.

8. **НЕ змінюй формат `$global:Actions`** у GUI -- масив PSCustomObject з полями Category, Name, Script, Desc.

## Catppuccin Mocha -- палітра кольорів GUI

| Призначення | Колір |
|---|---|
| Background | `#1e1e2e` |
| Surface | `#313244` |
| Overlay | `#45475a` |
| Text | `#cdd6f4` |
| Subtext | `#a6adc8` |
| Muted | `#6c7086` |
| Blue (headers) | `#89b4fa` |
| Mauve (accents) | `#cba6f7` |
| Green (success) | `#a6e3a1` |
| Peach (warning) | `#fab387` |
| Red (error) | `#f38ba8` |
