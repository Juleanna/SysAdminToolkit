SysAdminToolkit v5.0

Набор скриптов для типовых задач администрирования с простым WPF GUI и интеграцией с Telegram: инвентаризация, мониторинг, бэкапы, сеть, удалённая помощь.

Состав:
- SysAdminToolkit.GUI.ps1 — WPF-приложение-обёртка
- Scripts\Inventory — инвентаризация
- Scripts\Monitoring — мониторинг
- Scripts\Backup — резервное копирование
- Scripts\Network — сеть
- Scripts\Printers — принтеры
- Scripts\Profiles — профили пользователей
- Scripts\Mass — массовые операции
- Scripts\Security — быстрые проверки безопасности
- Scripts\Recovery — восстановление Windows
- Scripts\Utils — утилиты
- Scripts\Telegram — отправка в Telegram
- Scripts\RemoteHelp — удалённая помощь
- Config\ToolkitConfig.json — общий конфиг (сеть, бэкапы, описание)
- Config\Telegram.json — параметры Telegram-бота
- Logs\ — лог GUI

Быстрый старт:
1) Распакуйте каталог в удобное место (например, D:\SysAdminToolkit).
2) Откройте PowerShell от имени администратора.
3) Разрешите запуск локальных сценариев (если ещё не):
   Set-ExecutionPolicy RemoteSigned
4) Перейдите в каталог:
   cd D:\SysAdminToolkit
5) Заполните Config\Telegram.json (BotToken, ChatID) или отключите Enabled.
6) Запустите GUI:
   .\SysAdminToolkit.GUI.ps1

Передача параметров в GUI: в поле параметров указывайте пары вида `ИмяПараметра=значение;Имя2=значение2` — они будут переданы целевому скрипту как `-ИмяПараметра значение`.

Безопасность Telegram: задайте токен в переменной окружения `SYSADMINTK_BOTTOKEN`, чтобы не хранить его в файле.

Если при запуске задач видите ошибку про `param` — обновите файл `SysAdminToolkit.GUI.ps1` (последняя версия вызывает скрипты через `powershell.exe -File`, что исправляет эту проблему).
