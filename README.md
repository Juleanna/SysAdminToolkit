# SysAdmin Toolkit v5.0

**Комплексний набір PowerShell-скриптів для системного адміністрування з WPF GUI, інтеграцією Telegram та HTML-звітами.**

> Мова інтерфейсу: **українська**
> Платформа: Windows 10/11, Windows Server 2016+
> PowerShell: 5.1+

---

## Можливості

- **18 категорій**, **67+ скриптів** для щоденних завдань сисадміна
- **WPF GUI** з темною темою (Catppuccin Mocha) -- жодних консольних вікон для рутинних операцій
- **Telegram-інтеграція** -- сповіщення, алерти, відправка файлів та інвентаризації
- **HTML-звіти та дашборди** -- Catppuccin-стилізовані звіти, що генеруються автоматично
- **Pester-тести** -- каталог `Tests/` для автоматичного тестування
- **RBAC-ролі** -- Admin / Operator / Auditor через `Config/Roles.json`
- **Єдиний модуль** `ToolkitCommon.psm1` з 19 експортованими функціями
- **Логування** з ротацією, рівнями та записом до Windows Event Log
- **Retry / Timeout** -- автоматичні повторні спроби для мережевих операцій
- **DPAPI-збереження облікових даних** -- безпечне кешування credentials

## Категорії скриптів

| Категорія (UA) | Папка | Опис |
|---|---|---|
| Інвентаризація | `Scripts/Inventory` | Збір конфігурації ПК, список ПЗ |
| Моніторинг | `Scripts/Monitoring` | CPU/RAM, диски, сервіси, журнали |
| Сервіси | `Scripts/Services` | Монітор, перезапуск, автовідновлення |
| Диски | `Scripts/Disks` | SMART, простір, очищення, квоти |
| Сертифікати | `Scripts/Certificates` | Термін дії, встановлення |
| Заплановані завдання | `Scripts/ScheduledTasks` | Звіт, створення завдань |
| Бекапи | `Scripts/Backup` | Папки, профілі, GPO, завдання |
| Мережа | `Scripts/Network` | Пінг, LAN-сканування, порти, DNS |
| Принтери | `Scripts/Printers` | Додати, видалити, перезапуск Spooler |
| Профілі | `Scripts/Profiles` | Видалення старих, очищення |
| Масові операції | `Scripts/Mass` | Перезавантаження групи ПК, скрипти на хостах |
| Безпека | `Scripts/Security` | USB, Firewall, RDP, BitLocker, аудити, Defender |
| Відновлення | `Scripts/Recovery` | SFC + DISM, скидання мережі |
| Утиліти | `Scripts/Utils` | TEMP, збір логів, системна інформація |
| Telegram | `Scripts/Telegram` | Повідомлення, алерти, файли |
| Віддалена допомога | `Scripts/RemoteHelp` | Процеси, команди, логи, popup |
| Active Directory | `Scripts/ActiveDirectory` | Звіти користувачів AD |
| Звіти | `Scripts/Reports` | Спеціалізовані звіти |

## Швидкий старт

```powershell
# 1. Відкрийте PowerShell від імені адміністратора

# 2. Дозвольте виконання скриптів (якщо ще не дозволено)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 3. Перейдіть до каталогу
cd D:\SysAdminToolkit

# 4. (Опційно) Запустіть інсталятор
.\Install.ps1

# 5. Налаштуйте Telegram (за бажанням)
#    Відредагуйте Config\Telegram.json — вкажіть BotToken та ChatID
#    Або задайте змінну оточення: $env:SYSADMINTK_BOTTOKEN = "ваш_токен"

# 6. Запустіть GUI
.\SysAdminToolkit.GUI.ps1
```

## Структура проекту

```
SysAdminToolkit/
├── SysAdminToolkit.GUI.ps1          # Головний WPF GUI
├── Install.ps1                       # Інсталятор
├── Update-Toolkit.ps1                # Оновлення тулкіту
├── Config/
│   ├── ToolkitConfig.json            # Загальна конфігурація
│   ├── Telegram.json                 # Налаштування Telegram-бота
│   ├── Hosts.json                    # Список керованих ПК
│   └── Roles.json                    # RBAC-ролі
├── Scripts/
│   ├── ActiveDirectory/              # Active Directory
│   ├── Backup/                       # Резервне копіювання
│   ├── Certificates/                 # Сертифікати
│   ├── Disks/                        # Диски та сховище
│   ├── Inventory/                    # Інвентаризація
│   ├── Mass/                         # Масові операції
│   ├── Monitoring/                   # Моніторинг
│   ├── Network/                      # Мережа
│   ├── Printers/                     # Принтери
│   ├── Profiles/                     # Профілі користувачів
│   ├── Recovery/                     # Відновлення Windows
│   ├── RemoteHelp/                   # Віддалена допомога
│   ├── Reports/                      # Звіти
│   ├── ScheduledTasks/               # Заплановані завдання
│   ├── Security/                     # Безпека
│   ├── Services/                     # Windows-сервіси
│   ├── Telegram/                     # Telegram-інтеграція
│   └── Utils/
│       ├── ToolkitCommon.psm1        # Спільний модуль (19 функцій)
│       ├── Clean-Temp.ps1
│       ├── Collect-Logs.ps1
│       ├── Run-OnMultiple.ps1
│       └── System-Info.ps1
├── Logs/                             # Логи (авторотація)
├── Reports/                          # Згенеровані звіти
├── Tests/                            # Pester-тести
└── .PSScriptAnalyzerSettings.psd1    # Налаштування PSScriptAnalyzer
```

## Гарячі клавіші GUI

| Клавіша | Дія |
|---|---|
| **F5** | Виконати обрану операцію |
| **Esc** | Скасувати поточне виконання |
| **F1** | Показати довідку |
| Подвійний клік | Запустити операцію |

## Передача параметрів

У полі "Параметри" GUI введіть пари значень у форматі:

```
Ключ=Значення;Ключ2=Значення2
```

Приклади:
- `ServiceName=Spooler` -- для перезапуску конкретного сервісу
- `ComputerName=PC-01;Ports=80,443,3389` -- для тесту портів
- `Level=Warning;Title=Диск;Message=Мало місця` -- для Telegram-алерту
- `Path=C:\Temp;DaysOld=30` -- для очищення старих файлів

## Конфігурація

### ToolkitConfig.json

| Параметр | Опис | За замовчуванням |
|---|---|---|
| `CompanyName` | Назва організації | `"Dafna"` |
| `DefaultBackupPath` | Шлях для бекапів | `"D:/Backups"` |
| `Subnet` | Підмережа для сканування | `"192.168.1."` |
| `LogLevel` | Рівень логування (DEBUG/INFO/WARN/ERROR) | `"INFO"` |
| `MaxLogSizeMB` | Макс. розмір лог-файлу до ротації | `10` |
| `DiskSpaceWarningPercent` | Поріг попередження диску (%) | `80` |
| `DiskSpaceCriticalPercent` | Критичний поріг диску (%) | `95` |
| `CertExpiryWarnDays` | Днів до попередження про сертифікат | `30` |
| `CriticalServices` | Список критичних сервісів | `["Spooler", ...]` |
| `RemoteTimeoutSec` | Таймаут віддаленого підключення (сек) | `30` |
| `RetryCount` | Кількість повторних спроб | `3` |

### Telegram.json

| Параметр | Опис |
|---|---|
| `BotToken` | Токен Telegram-бота (або через `$env:SYSADMINTK_BOTTOKEN`) |
| `ChatID` | ID чату для повідомлень |
| `Enabled` | Увімкнути/вимкнути інтеграцію |

### Roles.json

Три ролі за замовчуванням:
- **Admin** -- повний доступ до всіх категорій
- **Operator** -- операційні категорії (моніторинг, бекапи, мережа та ін.)
- **Auditor** -- тільки перегляд (інвентаризація, моніторинг, звіти, безпека)

## Вимоги

- **ОС**: Windows 10 / 11 / Server 2016+ (x64)
- **PowerShell**: 5.1 або новіший
- **Права**: Адміністратор (для більшості операцій)
- **.NET Framework**: 4.7.2+ (для WPF GUI)
- **Опційно**: RSAT (для Active Directory та GPO скриптів)
- **Опційно**: Pester 5+ (для тестів)

## Безпека

- Telegram-токен можна передавати через змінну оточення `SYSADMINTK_BOTTOKEN`
- Облікові дані зберігаються через DPAPI (прив'язані до користувача та машини)
- RBAC обмежує доступ до категорій залежно від ролі
- Усі дії логуються у `Logs/Toolkit.log` та (опційно) Windows Event Log

## Ліцензія

MIT License. Вільне використання, модифікація та розповсюдження.
