Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms

$base        = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $base "Scripts\Utils\ToolkitCommon.psm1") -Force

$scriptsRoot = Join-Path $base "Scripts"
$logsRoot    = Join-Path $base "Logs"
$reportsRoot = Join-Path $base "Reports"
$favFile     = Join-Path $base "Config\.favorites.json"

if (-not (Test-Path $logsRoot))    { New-Item -ItemType Directory -Path $logsRoot    | Out-Null }
if (-not (Test-Path $reportsRoot)) { New-Item -ItemType Directory -Path $reportsRoot | Out-Null }

$cfg = Get-ToolkitConfig

# ============================================================
#  Обрані (Favorites)
# ============================================================
$script:Favorites = [System.Collections.Generic.HashSet[string]]::new()
if (Test-Path $favFile) {
    try { (Get-Content $favFile -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { [void]$script:Favorites.Add($_) } } catch {}
}
function Save-Favorites {
    @($script:Favorites) | ConvertTo-Json | Set-Content -Path $favFile -Encoding UTF8
}

# ============================================================
#  Дії (Actions)
# ============================================================
$global:Actions = @(
    # Інвентаризація
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Інвентаризація ПК"; Script="Inventory\Get-PC-Inventory.ps1"; Desc="Збір повної інформації про ПК" }
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Список встановленого ПЗ"; Script="Inventory\Get-InstalledSoftware.ps1"; Desc="Експорт ПЗ у CSV" }
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Надіслати інвентаризацію в TG"; Script="Telegram\Send-LastInventoryToTG.ps1"; Desc="Відправити інвентаризацію у Telegram" }
    # Моніторинг
    [PSCustomObject]@{ Category="Моніторинг"; Name="Перевірка продуктивності"; Script="Monitoring\Check-Performance.ps1"; Desc="CPU, RAM, диски — навантаження" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Експорт журналів"; Script="Monitoring\Export-EventLogs.ps1"; Desc="Збереження журналів у файл" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Аптайм критичних сервісів"; Script="Monitoring\Check-ServiceUptime.ps1"; Desc="Статус сервісів з конфігу" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Перевірка дисків"; Script="Monitoring\Check-DiskSpace.ps1"; Desc="Вільне місце з порогами" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Моніторинг подій"; Script="Monitoring\Watch-EventLog.ps1"; Desc="Реактивний моніторинг Event Log" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Очікує перезавантаження?"; Script="Monitoring\Check-PendingReboot.ps1"; Desc="Перевірка необхідності ребуту" }
    # Сервіси
    [PSCustomObject]@{ Category="Сервіси"; Name="Монітор сервісів"; Script="Services\Service-Monitor.ps1"; Desc="Дашборд критичних сервісів" }
    [PSCustomObject]@{ Category="Сервіси"; Name="Перезапуск сервісу"; Script="Services\Service-Restart.ps1"; Desc="Перезапуск з залежностями (ServiceName=...)" }
    [PSCustomObject]@{ Category="Сервіси"; Name="Автовідновлення"; Script="Services\Service-AutoRecover.ps1"; Desc="Автоперезапуск при збої" }
    # Диски
    [PSCustomObject]@{ Category="Диски"; Name="SMART-статус"; Script="Disks\Disk-Health.ps1"; Desc="Здоров'я фізичних дисків" }
    [PSCustomObject]@{ Category="Диски"; Name="Звіт простору"; Script="Disks\Disk-SpaceReport.ps1"; Desc="Детальний звіт дисків" }
    [PSCustomObject]@{ Category="Диски"; Name="Очищення старих файлів"; Script="Disks\Cleanup-OldFiles.ps1"; Desc="Видалення файлів >N днів" }
    [PSCustomObject]@{ Category="Диски"; Name="Квоти профілів"; Script="Disks\Disk-QuotaReport.ps1"; Desc="Розмір профілів" }
    [PSCustomObject]@{ Category="Диски"; Name="Оптимізація диска"; Script="Disks\Optimize-Disk.ps1"; Desc="Дефрагментація HDD / TRIM SSD (DriveLetter=C;Mode=Analyze|Optimize|Retrim)" }
    # Сертифікати
    [PSCustomObject]@{ Category="Сертифікати"; Name="Термін сертифікатів"; Script="Certificates\Cert-ExpiryCheck.ps1"; Desc="Пошук сертифікатів що спливають" }
    [PSCustomObject]@{ Category="Сертифікати"; Name="Встановити сертифікат"; Script="Certificates\Cert-Install.ps1"; Desc="Імпорт сертифікату (CertPath=...)" }
    # Заплановані завдання
    [PSCustomObject]@{ Category="Завдання"; Name="Звіт планувальника"; Script="ScheduledTasks\ScheduledTask-Report.ps1"; Desc="Список завдань зі статусом" }
    [PSCustomObject]@{ Category="Завдання"; Name="Створити завдання"; Script="ScheduledTasks\ScheduledTask-Create.ps1"; Desc="Нове заплановане завдання" }
    # Бекапи
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап папки"; Script="Backup\Backup-Folder.ps1"; Desc="Архівація папки у ZIP" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап профілів"; Script="Backup\Backup-UserProfiles.ps1"; Desc="Резервне копіювання профілів" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап завдань"; Script="Backup\Backup-ScheduledTask.ps1"; Desc="Експорт завдань у XML" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап GPO"; Script="Backup\Backup-GPO.ps1"; Desc="Резервне копіювання GPO" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап реєстру"; Script="Backup\Backup-Registry.ps1"; Desc="Експорт гілок реєстру (SpecificKey=HKLM\\SOFTWARE\\...)" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап драйверів"; Script="Backup\Backup-Drivers.ps1"; Desc="Експорт сторонніх драйверів для переустановки" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Очищення старих бекапів"; Script="Backup\Clean-OldBackups.ps1"; Desc="Видалення бекапів >N днів (RetentionDays=30;WhatIf=true)" }
    # Мережа
    [PSCustomObject]@{ Category="Мережа"; Name="Перевірка мережі"; Script="Network\Test-Network.ps1"; Desc="Діагностика підключення" }
    [PSCustomObject]@{ Category="Мережа"; Name="Сканування LAN"; Script="Network\Scan-LAN.ps1"; Desc="Пошук хостів у підмережі" }
    [PSCustomObject]@{ Category="Мережа"; Name="Відновлення мережі"; Script="Recovery\Repair-Network.ps1"; Desc="Скидання DNS/Winsock/IP" }
    [PSCustomObject]@{ Category="Мережа"; Name="Тест портів"; Script="Network\Test-Ports.ps1"; Desc="TCP-порти (ComputerName=...;Ports=...)" }
    [PSCustomObject]@{ Category="Мережа"; Name="DNS-записи"; Script="Network\Get-DNSRecords.ps1"; Desc="Запит DNS (DomainName=...)" }
    [PSCustomObject]@{ Category="Мережа"; Name="Traceroute"; Script="Network\Trace-Route.ps1"; Desc="Візуальний маршрут (Target=...)" }
    [PSCustomObject]@{ Category="Мережа"; Name="Тест пропускності"; Script="Network\Test-Bandwidth.ps1"; Desc="Швидкість між ПК (ComputerName=...)" }
    # Принтери
    [PSCustomObject]@{ Category="Принтери"; Name="Додати принтер"; Script="Printers\Add-NetworkPrinter.ps1"; Desc="Мережевий принтер" }
    [PSCustomObject]@{ Category="Принтери"; Name="Видалити принтер"; Script="Printers\Remove-Printer.ps1"; Desc="Видалення принтера" }
    [PSCustomObject]@{ Category="Принтери"; Name="Перезапуск Spooler"; Script="Printers\Restart-Spooler.ps1"; Desc="Print Spooler" }
    # Профілі
    [PSCustomObject]@{ Category="Профілі"; Name="Видалити старі профілі"; Script="Profiles\Delete-OldProfiles.ps1"; Desc="Профілі >N днів (-WhatIf)" }
    [PSCustomObject]@{ Category="Профілі"; Name="Очистити профіль"; Script="Profiles\Clean-UserProfile.ps1"; Desc="Кеш та тимчасові файли" }
    # Масові
    [PSCustomObject]@{ Category="Масові операції"; Name="Перезавантажити ПК"; Script="Mass\Restart-Computers.ps1"; Desc="Перезавантаження зі списку (-WhatIf)" }
    [PSCustomObject]@{ Category="Масові операції"; Name="Запуск на групі"; Script="Mass\Run-OnMultiple.ps1"; Desc="Скрипт на хостах з Hosts.json" }
    # Active Directory
    [PSCustomObject]@{ Category="Active Directory"; Name="Звіт користувачів AD"; Script="ActiveDirectory\AD-UserReport.ps1"; Desc="Неактивні, заблоковані, прострочені" }
    [PSCustomObject]@{ Category="Active Directory"; Name="Звіт комп'ютерів AD"; Script="ActiveDirectory\AD-ComputerReport.ps1"; Desc="Застарілі ПК, статистика за ОС" }
    [PSCustomObject]@{ Category="Active Directory"; Name="Членство у групі"; Script="ActiveDirectory\AD-GroupMembership.ps1"; Desc="Члени AD-групи (GroupName=...)" }
    # Безпека
    [PSCustomObject]@{ Category="Безпека"; Name="USB (Вкл/Викл)"; Script="Security\Toggle-USBStorage.ps1"; Desc="USB-носії через реєстр" }
    [PSCustomObject]@{ Category="Безпека"; Name="Адміністратори"; Script="Security\List-LocalAdmins.ps1"; Desc="Група Адміністратори" }
    [PSCustomObject]@{ Category="Безпека"; Name="Перевірка загроз"; Script="Security\Quick-Malware-Check.ps1"; Desc="Підозрілі процеси" }
    [PSCustomObject]@{ Category="Безпека"; Name="Брандмауер"; Script="Security\Firewall-Profile.ps1"; Desc="Windows Firewall" }
    [PSCustomObject]@{ Category="Безпека"; Name="RDP + NLA"; Script="Security\Toggle-RDP.ps1"; Desc="Remote Desktop" }
    [PSCustomObject]@{ Category="Безпека"; Name="Паролі (звіт)"; Script="Security\PasswordPolicy-Report.ps1"; Desc="Вимоги до паролів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Defender сканування"; Script="Security\Defender-QuickScan.ps1"; Desc="Швидке сканування" }
    [PSCustomObject]@{ Category="Безпека"; Name="BitLocker"; Script="Security\BitLocker-Status.ps1"; Desc="Стан шифрування" }
    [PSCustomObject]@{ Category="Безпека"; Name="Локальні користувачі"; Script="Security\LocalUsers-Report.ps1"; Desc="Всі облікові записи" }
    [PSCustomObject]@{ Category="Безпека"; Name="Керування користувачами"; Script="Security\LocalUser-Manage.ps1"; Desc="Mode=Create|Enable|Disable|ResetPassword|Rename|Delete;Username=...;Password=...;NewName=..." }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит безпеки"; Script="Security\Audit-Report.ps1"; Desc="Аудит Event Log" }
    [PSCustomObject]@{ Category="Безпека"; Name="WinRM/SMB/NTLM"; Script="Security\RemoteAccess-Hardening.ps1"; Desc="Посилення віддаленого доступу" }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит-політики"; Script="Security\AuditPolicy-Apply.ps1"; Desc="Політики аудиту" }
    [PSCustomObject]@{ Category="Безпека"; Name="LSA/SmartScreen"; Script="Security\AccountProtection.ps1"; Desc="Захист облікових записів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Автозапуск"; Script="Security\Autoruns-Report.ps1"; Desc="Автозапуск/сервіси" }
    [PSCustomObject]@{ Category="Безпека"; Name="Оновлення безпеки"; Script="Security\SecurityUpdates.ps1"; Desc="Оновлення й сигнатури" }
    [PSCustomObject]@{ Category="Безпека"; Name="Спільні папки"; Script="Security\Audit-SharedFolders.ps1"; Desc="Мережеві ресурси та права" }
    [PSCustomObject]@{ Category="Безпека"; Name="Відкриті порти"; Script="Security\Check-OpenPorts.ps1"; Desc="TCP/UDP та процеси" }
    [PSCustomObject]@{ Category="Безпека"; Name="Security Baseline"; Script="Security\Export-SecurityBaseline.ps1"; Desc="Знімок безпеки" }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит NTFS-прав"; Script="Security\Audit-Permissions.ps1"; Desc="Рекурсивний аудит ACL (Path=...)" }
    [PSCustomObject]@{ Category="Безпека"; Name="Слабкі паролі"; Script="Security\Check-WeakPasswords.ps1"; Desc="Пошук слабких/порожніх паролів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Підпис скриптів"; Script="Security\Sign-Scripts.ps1"; Desc="CodeSigning (CertThumbprint=...)" }
    # Відновлення
    [PSCustomObject]@{ Category="Відновлення"; Name="SFC + DISM"; Script="Recovery\Repair-Windows.ps1"; Desc="Перевірка системних файлів" }
    [PSCustomObject]@{ Category="Відновлення"; Name="Відновити профіль"; Script="Recovery\Restore-UserProfile.ps1"; Desc="З бекапу (BackupPath=...;Username=...)" }
    [PSCustomObject]@{ Category="Відновлення"; Name="Перевірка диска (chkdsk)"; Script="Recovery\Repair-DiskErrors.ps1"; Desc="Перевірка та ремонт диска (DriveLetter=C;Mode=Check|Fix|Full)" }
    [PSCustomObject]@{ Category="Відновлення"; Name="Скидання Windows Update"; Script="Recovery\Reset-WindowsUpdate.ps1"; Desc="Скидання компонентів оновлення Windows" }
    [PSCustomObject]@{ Category="Відновлення"; Name="Точки відновлення"; Script="Recovery\Manage-RestorePoints.ps1"; Desc="Створити/переглянути/очистити (Mode=List|Create|DeleteOld)" }
    # Утиліти
    [PSCustomObject]@{ Category="Утиліти"; Name="Очистити TEMP"; Script="Utils\Clean-Temp.ps1"; Desc="Тимчасові файли (-WhatIf)" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Збір логів"; Script="Utils\Collect-Logs.ps1"; Desc="Логи в архів" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Інфо про систему"; Script="Utils\System-Info.ps1"; Desc="ОС, CPU, RAM, мережа" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Порівняння ПК"; Script="Utils\Compare-Configs.ps1"; Desc="Відмінності двох ПК" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Створити ISO"; Script="Utils\New-ISOImage.ps1"; Desc="ISO з папки (SourcePath=...;OutputPath=...)" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Очищення системного сміття"; Script="Utils\Clean-SystemJunk.ps1"; Desc="Комплексне очищення: temp, prefetch, кеш, дампи, кошик (-WhatIf)" }
    # Звіти
    [PSCustomObject]@{ Category="Звіти"; Name="Щоденний звіт"; Script="Reports\Daily-Report.ps1"; Desc="Зведений звіт: диски, сервіси, безпека" }
    [PSCustomObject]@{ Category="Звіти"; Name="Знімок/Порівняння"; Script="Reports\Compare-Snapshot.ps1"; Desc="Базовий знімок або diff" }
    # Telegram
    [PSCustomObject]@{ Category="Telegram"; Name="Тестове повідомлення"; Script="Telegram\Test-TGMessage.ps1"; Desc="Тест Telegram-з'єднання" }
    [PSCustomObject]@{ Category="Telegram"; Name="Сповіщення"; Script="Telegram\Send-TGAlert.ps1"; Desc="Алерт (Level=...;Title=...;Message=...)" }
    # Віддалена допомога
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Процеси"; Script="RemoteHelp\Get-RemoteProcesses.ps1"; Desc="Процеси на віддаленому ПК" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Завершити процес"; Script="RemoteHelp\Kill-RemoteProcess.ps1"; Desc="Kill процесу" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Повідомлення"; Script="RemoteHelp\Popup-Message.ps1"; Desc="Popup на екрані" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Збір логів"; Script="RemoteHelp\Collect-RemoteLogs.ps1"; Desc="Логи з віддаленого ПК" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Команда"; Script="RemoteHelp\Run-RemoteCommand.ps1"; Desc="PowerShell на віддаленому ПК" }
)

# Фільтрація за ролями
$userRole = Get-TkUserRole
$categories = @("Обрані") + @($Actions | Select-Object -ExpandProperty Category -Unique | Sort-Object)

# ============================================================
#  Історія / System Monitor
# ============================================================
$script:ExecutionHistory = [System.Collections.ArrayList]::new()

# ============================================================
#  XAML — Dark Theme + StatusBar + Favorites + ViewCode + Schedule
# ============================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SysAdmin Toolkit v5.0 — $($cfg.CompanyName)" Height="820" Width="1160"
        WindowStartupLocation="CenterScreen" Background="#1e1e2e" Foreground="#cdd6f4">
  <Window.Resources>
    <Style TargetType="GroupBox"><Setter Property="Foreground" Value="#cba6f7"/><Setter Property="BorderBrush" Value="#45475a"/><Setter Property="BorderThickness" Value="1"/></Style>
    <Style TargetType="ListBox"><Setter Property="Background" Value="#313244"/><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="BorderBrush" Value="#45475a"/></Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="#313244"/><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="BorderBrush" Value="#45475a"/><Setter Property="CaretBrush" Value="#cdd6f4"/></Style>
    <Style TargetType="Button"><Setter Property="Background" Value="#45475a"/><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="BorderBrush" Value="#585b70"/><Setter Property="Padding" Value="8,3"/><Setter Property="Cursor" Value="Hand"/></Style>
    <Style TargetType="TabControl"><Setter Property="Background" Value="#1e1e2e"/><Setter Property="BorderBrush" Value="#45475a"/></Style>
    <Style TargetType="TabItem"><Setter Property="Foreground" Value="#a6adc8"/><Setter Property="Background" Value="#313244"/><Setter Property="Padding" Value="10,4"/>
      <Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Foreground" Value="#cba6f7"/><Setter Property="Background" Value="#45475a"/></Trigger></Style.Triggers>
    </Style>
    <Style TargetType="ProgressBar"><Setter Property="Background" Value="#313244"/><Setter Property="Foreground" Value="#89b4fa"/><Setter Property="BorderBrush" Value="#45475a"/></Style>
    <Style TargetType="DataGrid"><Setter Property="Background" Value="#313244"/><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="BorderBrush" Value="#45475a"/><Setter Property="RowBackground" Value="#313244"/><Setter Property="AlternatingRowBackground" Value="#3b3d52"/><Setter Property="GridLinesVisibility" Value="None"/><Setter Property="HeadersVisibility" Value="Column"/></Style>
  </Window.Resources>
  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="2*"/><RowDefinition Height="Auto"/><RowDefinition Height="1.2*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

    <StackPanel Grid.Row="0" Grid.ColumnSpan="2" Margin="0,0,0,6">
      <TextBlock Text="SysAdmin Toolkit v5.0" FontSize="18" FontWeight="Bold" Foreground="#89b4fa"/>
      <TextBlock Text="$($cfg.CompanyName) | $($env:COMPUTERNAME) | Роль: $userRole" FontSize="10" Foreground="#6c7086"/>
    </StackPanel>

    <Grid Grid.Row="1" Grid.ColumnSpan="2" Margin="0,0,0,6">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <TextBlock Text="Пошук:" Foreground="#a6adc8" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox Name="txtSearch" Grid.Column="1" Height="24"/>
    </Grid>

    <GroupBox Grid.Row="2" Grid.Column="0" Header="Категорії" Margin="0,0,6,6">
      <ListBox Name="lbCategories" FontSize="12"/>
    </GroupBox>

    <GroupBox Grid.Row="2" Grid.Column="1" Header="Операції" Margin="0,0,0,6">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListBox Name="lbActions" Grid.Row="0" DisplayMemberPath="Name" FontSize="12"/>
        <TextBlock Name="lblDesc" Grid.Row="1" Foreground="#a6adc8" FontSize="10" TextWrapping="Wrap" Margin="4,3,4,0" MinHeight="16"/>
        <StackPanel Grid.Row="2" Orientation="Vertical" Margin="0,4,0,0">
          <TextBlock Text="Параметри (Ключ=Значення;Ключ2=Значення2)" FontSize="10" Foreground="#6c7086"/>
          <TextBox Name="txtParams" Height="24"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,5,0,0">
          <Button Name="btnFav" Content="&#9733;" Height="28" Width="32" ToolTip="Додати/Прибрати з обраних" Margin="0,0,4,0"/>
          <Button Name="btnViewCode" Content="Код" Height="28" Width="50" ToolTip="Переглянути скрипт" Margin="0,0,4,0"/>
          <Button Name="btnSchedule" Content="План." Height="28" Width="50" ToolTip="Запланувати у Task Scheduler" Margin="0,0,4,0"/>
          <Button Name="btnRun" Content="Виконати (F5)" Height="28" Width="120" Margin="0,0,4,0"/>
          <Button Name="btnCancel" Content="Скасувати (Esc)" Height="28" Width="120" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </GroupBox>

    <StackPanel Grid.Row="3" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,0,0,3">
      <TextBlock Text="Прогрес:" Foreground="#a6adc8" VerticalAlignment="Center" Margin="0,0,4,0"/>
      <ProgressBar Name="pbStatus" Minimum="0" Maximum="100" Height="14" Width="280"/>
      <TextBlock Name="lblProgress" Foreground="#a6e3a1" Margin="6,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>

    <TabControl Grid.Row="4" Grid.ColumnSpan="2">
      <TabItem Header="Лог">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <RichTextBox Name="rtbLog" Background="#181825" Foreground="#cdd6f4" BorderBrush="#45475a" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" IsReadOnly="True" FontFamily="Consolas" FontSize="11">
            <RichTextBox.Document><FlowDocument PageWidth="5000"><Paragraph Name="logParagraph"/></FlowDocument></RichTextBox.Document>
          </RichTextBox>
          <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,3,0,0">
            <Button Name="btnExportLog" Content="Експорт" Height="24" Width="80" Margin="0,0,4,0"/>
            <Button Name="btnClearLog" Content="Очистити" Height="24" Width="80"/>
          </StackPanel>
        </Grid>
      </TabItem>
      <TabItem Header="Історія">
        <DataGrid Name="dgHistory" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" ColumnHeaderHeight="26" RowHeight="22">
          <DataGrid.ColumnHeaderStyle><Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#45475a"/><Setter Property="Foreground" Value="#cba6f7"/><Setter Property="Padding" Value="6,2"/></Style></DataGrid.ColumnHeaderStyle>
          <DataGrid.Columns>
            <DataGridTextColumn Header="Час" Binding="{Binding Time}" Width="130"/>
            <DataGridTextColumn Header="Дія" Binding="{Binding Action}" Width="*"/>
            <DataGridTextColumn Header="Статус" Binding="{Binding Status}" Width="90"/>
            <DataGridTextColumn Header="Час вик." Binding="{Binding Duration}" Width="80"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
    </TabControl>

    <!-- StatusBar -->
    <Border Grid.Row="5" Grid.ColumnSpan="2" Background="#181825" CornerRadius="3" Margin="0,4,0,0" Padding="8,3">
      <StackPanel Orientation="Horizontal">
        <TextBlock Name="lblCPU" Text="CPU: --%" Foreground="#89b4fa" Margin="0,0,16,0" FontSize="11"/>
        <TextBlock Name="lblRAM" Text="RAM: --%" Foreground="#a6e3a1" Margin="0,0,16,0" FontSize="11"/>
        <TextBlock Name="lblDisk" Text="C: --%" Foreground="#fab387" Margin="0,0,16,0" FontSize="11"/>
        <TextBlock Name="lblUptime" Text="Аптайм: --" Foreground="#6c7086" FontSize="11"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ============================================================
#  Елементи UI
# ============================================================
$lbCategories = $window.FindName("lbCategories")
$lbActions    = $window.FindName("lbActions")
$btnRun       = $window.FindName("btnRun")
$btnCancel    = $window.FindName("btnCancel")
$btnFav       = $window.FindName("btnFav")
$btnViewCode  = $window.FindName("btnViewCode")
$btnSchedule  = $window.FindName("btnSchedule")
$rtbLog       = $window.FindName("rtbLog")
$txtParams    = $window.FindName("txtParams")
$txtSearch    = $window.FindName("txtSearch")
$pbStatus     = $window.FindName("pbStatus")
$lblProgress  = $window.FindName("lblProgress")
$lblDesc      = $window.FindName("lblDesc")
$btnExportLog = $window.FindName("btnExportLog")
$btnClearLog  = $window.FindName("btnClearLog")
$dgHistory    = $window.FindName("dgHistory")
$lblCPU       = $window.FindName("lblCPU")
$lblRAM       = $window.FindName("lblRAM")
$lblDisk      = $window.FindName("lblDisk")
$lblUptime    = $window.FindName("lblUptime")

$lbCategories.ItemsSource = $categories

# ============================================================
#  Log helpers
# ============================================================
function Write-LogLine { param([string]$Text, [string]$Color = "#cdd6f4")
    $doc = $rtbLog.Document; $para = $doc.Blocks.LastBlock
    if ($null -eq $para) { $para = New-Object System.Windows.Documents.Paragraph; $doc.Blocks.Add($para) }
    $run = New-Object System.Windows.Documents.Run("$Text`r`n")
    try { $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color) } catch { $run.Foreground = [System.Windows.Media.Brushes]::White }
    $para.Inlines.Add($run); $rtbLog.ScrollToEnd()
}
function Clear-Log { $rtbLog.Document.Blocks.Clear(); $rtbLog.Document.Blocks.Add((New-Object System.Windows.Documents.Paragraph)) }
function Get-LogText { (New-Object System.Windows.Documents.TextRange($rtbLog.Document.ContentStart, $rtbLog.Document.ContentEnd)).Text }

# ============================================================
#  Фільтрація
# ============================================================
function Update-ActionsList {
    $search = $txtSearch.Text.Trim().ToLower()
    $cat = $lbCategories.SelectedItem
    if ([string]::IsNullOrEmpty($search)) {
        if ($cat -eq "Обрані") {
            $items = @($Actions | Where-Object { $script:Favorites.Contains($_.Script) })
        } elseif ($null -eq $cat) { $items = @() }
        else { $items = @($Actions | Where-Object { $_.Category -eq $cat }) }
    } else {
        $items = @($Actions | Where-Object { $_.Name.ToLower().Contains($search) -or $_.Desc.ToLower().Contains($search) })
    }
    # Фільтр за роллю
    if (-not (Test-TkRoleAccess -Category "*")) {
        $items = @($items | Where-Object { Test-TkRoleAccess -Category $_.Category })
    }
    $lbActions.ItemsSource = $items
    $lblDesc.Text = ""
}

$lbCategories.Add_SelectionChanged({ Update-ActionsList })
$txtSearch.Add_TextChanged({
    if (-not [string]::IsNullOrEmpty($txtSearch.Text.Trim())) { $lbCategories.SelectedIndex = -1 }
    Update-ActionsList
})
$lbActions.Add_SelectionChanged({
    $sel = $lbActions.SelectedItem
    if ($null -ne $sel -and $sel.Desc) { $lblDesc.Text = $sel.Desc } else { $lblDesc.Text = "" }
})

# ============================================================
#  Favorites
# ============================================================
$btnFav.Add_Click({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    if ($script:Favorites.Contains($sel.Script)) { [void]$script:Favorites.Remove($sel.Script); Write-LogLine "Прибрано з обраних: $($sel.Name)" -Color "#fab387" }
    else { [void]$script:Favorites.Add($sel.Script); Write-LogLine "Додано в обрані: $($sel.Name)" -Color "#a6e3a1" }
    Save-Favorites
})

# ============================================================
#  View Code
# ============================================================
$btnViewCode.Add_Click({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $scriptPath = Join-Path $scriptsRoot $sel.Script
    if (-not (Test-Path $scriptPath)) { Write-LogLine "Файл не знайдено: $scriptPath" -Color "#f38ba8"; return }
    $code = Get-Content $scriptPath -Raw -Encoding UTF8
    $codeWin = New-Object System.Windows.Window
    $codeWin.Title = $sel.Name
    $codeWin.Width = 800; $codeWin.Height = 600
    $codeWin.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1e1e2e")
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $code; $tb.IsReadOnly = $true; $tb.AcceptsReturn = $true
    $tb.VerticalScrollBarVisibility = "Auto"; $tb.HorizontalScrollBarVisibility = "Auto"
    $tb.FontFamily = "Consolas"; $tb.FontSize = 12; $tb.TextWrapping = "NoWrap"
    $tb.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#181825")
    $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#cdd6f4")
    $codeWin.Content = $tb
    $codeWin.ShowDialog() | Out-Null
})

# ============================================================
#  Schedule
# ============================================================
$btnSchedule.Add_Click({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $scriptPath = Join-Path $scriptsRoot $sel.Script
    $taskName = "SysAdminTK_$($sel.Name -replace '\s+','_' -replace '[^\w]','')"
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "08:00"
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description $sel.Desc -Force | Out-Null
        Write-LogLine "Завдання створено: $taskName (щодня о 08:00)" -Color "#a6e3a1"
        Write-TkLog "Заплановано: $taskName" -Level INFO
    } catch {
        Write-LogLine "Помилка планування: $($_.Exception.Message)" -Color "#f38ba8"
    }
})

# ============================================================
#  Job execution
# ============================================================
$script:currentJob = $null; $script:lastOutputIndex = 0; $script:jobStartTime = $null; $script:currentActionName = ""

$script:jobTimer = New-Object Windows.Threading.DispatcherTimer
$script:jobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:jobTimer.Add_Tick({
    if ($null -eq $script:currentJob) { $script:jobTimer.Stop(); return }
    try {
        $allOutput = Receive-Job -Job $script:currentJob -Keep -ErrorAction SilentlyContinue
        if ($allOutput) {
            $newLines = @($allOutput)[$script:lastOutputIndex..($allOutput.Count - 1)]
            $script:lastOutputIndex = @($allOutput).Count
            foreach ($line in $newLines) {
                $lineStr = "$line"
                if ($lineStr -match '^PROGRESS:\s*(\d+)') { $pbStatus.Value = [math]::Min(100,[int]$Matches[1]); $lblProgress.Text = "$($Matches[1])%"; continue }
                $color = "#cdd6f4"
                if ($lineStr -match '(помилка|error|fail|не вдалося)') { $color = "#f38ba8" }
                elseif ($lineStr -match '(попередження|warning|увага)') { $color = "#fab387" }
                elseif ($lineStr -match '(успішно|success|done|ok|завершено)') { $color = "#a6e3a1" }
                Write-LogLine $lineStr -Color $color
            }
        }
    } catch {}
    if ($script:currentJob.State -in @("Completed","Failed","Stopped")) {
        $script:jobTimer.Stop()
        $result = Receive-Job -Job $script:currentJob -ErrorAction SilentlyContinue
        $state = $script:currentJob.State
        Remove-Job $script:currentJob -Force -ErrorAction SilentlyContinue
        $script:currentJob = $null; $script:lastOutputIndex = 0
        $btnRun.IsEnabled = $true; $btnCancel.IsEnabled = $false
        $pbStatus.Value = 0; $lblProgress.Text = ""
        $duration = ""; if ($script:jobStartTime) { $duration = "{0:mm\:ss}" -f ((Get-Date) - $script:jobStartTime) }
        $status = "Успішно"; $logColor = "#a6e3a1"; $logLevel = "INFO"
        if ($state -eq "Stopped") { $status = "Скасовано"; $logColor = "#fab387"; $logLevel = "WARN" }
        elseif (-not ($result -and $result.Success)) { $status = "Помилка"; $logColor = "#f38ba8"; $logLevel = "ERROR" }
        Write-LogLine "--- $status ---" -Color $logColor
        Write-TkLog "$status`: $($script:currentActionName)" -Level $logLevel
        Write-TkEventLog "$status`: $($script:currentActionName)" -EntryType $(if($status -eq "Помилка"){"Error"}elseif($status -eq "Скасовано"){"Warning"}else{"Information"})
        [void]$script:ExecutionHistory.Add([PSCustomObject]@{ Time=(Get-Date -Format "yyyy-MM-dd HH:mm:ss"); Action=$script:currentActionName; Status=$status; Duration=$duration })
        $dgHistory.ItemsSource = $null; $dgHistory.ItemsSource = $script:ExecutionHistory
    }
})

function Invoke-ToolkitScript { param([string]$RelativePath, [string]$DisplayName, [hashtable]$ArgsHashtable)
    if ($script:currentJob) { Write-LogLine "Зачекайте або скасуйте." -Color "#fab387"; return }
    $scriptPath = Join-Path $scriptsRoot $RelativePath
    if (-not (Test-Path $scriptPath)) { Write-LogLine "Не знайдено: $scriptPath" -Color "#f38ba8"; return }
    Clear-Log; Write-LogLine "Запуск: $DisplayName" -Color "#89b4fa"; Write-LogLine $scriptPath -Color "#6c7086"; Write-LogLine "---" -Color "#45475a"
    Write-TkLog "Старт: $DisplayName ($scriptPath)" -Level INFO
    $btnRun.IsEnabled = $false; $btnCancel.IsEnabled = $true; $pbStatus.Value = 0; $lblProgress.Text = ""
    $script:lastOutputIndex = 0; $script:jobStartTime = Get-Date; $script:currentActionName = $DisplayName
    $argArray = @(); foreach ($k in $ArgsHashtable.Keys) { $argArray += "-$k"; $argArray += $ArgsHashtable[$k] }
    $script:currentJob = Start-Job -ScriptBlock {
        param($sp,$dn,$aa,$wd); Set-Location $wd
        $r = [pscustomobject]@{ Success=$false; Output=""; ErrorMessage=""; DisplayName=$dn }
        try { $r.Output = & $sp @aa *>&1 | Out-String; $r.Success = $true } catch { $r.ErrorMessage = $_.Exception.Message }
        return $r
    } -ArgumentList $scriptPath,$DisplayName,$argArray,$base
    $script:jobTimer.Start()
}

# Button handlers
$btnRun.Add_Click({ $sel = $lbActions.SelectedItem; if ($sel) { Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable (ConvertFrom-ParamString $txtParams.Text) } })
$btnCancel.Add_Click({ if ($script:currentJob) { Stop-Job $script:currentJob -Force -ErrorAction SilentlyContinue } })
$lbActions.Add_MouseDoubleClick({ $sel = $lbActions.SelectedItem; if ($sel) { Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable (ConvertFrom-ParamString $txtParams.Text) } })
$btnExportLog.Add_Click({
    $text = Get-LogText; if ([string]::IsNullOrWhiteSpace($text)) { return }
    $p = Join-Path $reportsRoot "GUILog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    try { Set-Content -Path $p -Value $text -Encoding UTF8; Write-LogLine "Експорт: $p" -Color "#a6e3a1" } catch { Write-LogLine "Помилка: $($_.Exception.Message)" -Color "#f38ba8" }
})
$btnClearLog.Add_Click({ Clear-Log })

# ============================================================
#  StatusBar timer (30s)
# ============================================================
$script:statusTimer = New-Object Windows.Threading.DispatcherTimer
$script:statusTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:statusTimer.Add_Tick({
    try {
        $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
        $lblCPU.Text = "CPU: $cpu%"
        $os = Get-CimInstance Win32_OperatingSystem
        $ramPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 0)
        $lblRAM.Text = "RAM: $ramPct%"
        $cDrive = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($cDrive -and $cDrive.Size -gt 0) {
            $diskPct = [math]::Round(($cDrive.Size - $cDrive.SizeRemaining) / $cDrive.Size * 100, 0)
            $lblDisk.Text = "C: $diskPct%"
        }
        $uptime = (Get-Date) - $os.LastBootUpTime
        $lblUptime.Text = "Аптайм: $([int]$uptime.TotalDays)д $($uptime.ToString('hh\:mm'))"
    } catch {}
})
$script:statusTimer.Start()
# Initial status update
try {
    $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
    $lblCPU.Text = "CPU: $cpu%"
    $os = Get-CimInstance Win32_OperatingSystem
    $ramPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 0)
    $lblRAM.Text = "RAM: $ramPct%"
    $cDrive = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($cDrive -and $cDrive.Size -gt 0) { $diskPct = [math]::Round(($cDrive.Size - $cDrive.SizeRemaining) / $cDrive.Size * 100, 0); $lblDisk.Text = "C: $diskPct%" }
    $uptime = (Get-Date) - $os.LastBootUpTime
    $lblUptime.Text = "Аптайм: $([int]$uptime.TotalDays)д $($uptime.ToString('hh\:mm'))"
} catch {}

# ============================================================
#  Tray icon
# ============================================================
$script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcon.Icon = [System.Drawing.SystemIcons]::Application
$script:trayIcon.Text = "SysAdmin Toolkit v5.0"
$script:trayIcon.Visible = $false
$script:trayIcon.Add_DoubleClick({ $window.Show(); $window.WindowState = 'Normal'; $script:trayIcon.Visible = $false })

$window.Add_StateChanged({
    if ($window.WindowState -eq 'Minimized') {
        $window.Hide()
        $script:trayIcon.Visible = $true
        $script:trayIcon.ShowBalloonTip(2000, "SysAdmin Toolkit", "Згорнуто у трей", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# ============================================================
#  Hotkeys
# ============================================================
$window.Add_KeyDown({
    param($sender, $e)
    switch ($e.Key) {
        'F5' { $sel = $lbActions.SelectedItem; if ($sel -and $btnRun.IsEnabled) { Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable (ConvertFrom-ParamString $txtParams.Text) }; $e.Handled = $true }
        'Escape' { if ($script:currentJob) { Stop-Job $script:currentJob -Force -ErrorAction SilentlyContinue }; $e.Handled = $true }
        'F1' {
            Clear-Log
            Write-LogLine "=== SysAdmin Toolkit v5.0 — Довідка ===" -Color "#89b4fa"
            Write-LogLine "F5  — Виконати | Esc — Скасувати | F1 — Довідка" -Color "#a6e3a1"
            Write-LogLine "Пошук — фільтрує дії | Подвійний клік — запуск" -Color "#cdd6f4"
            Write-LogLine "Зірочка — обрані | Код — перегляд скрипту" -Color "#cba6f7"
            Write-LogLine "План. — запланувати у Task Scheduler" -Color "#cba6f7"
            Write-LogLine "Мінімізація — згортання у трей" -Color "#6c7086"
            $e.Handled = $true
        }
    }
})

# ============================================================
#  Init
# ============================================================
$lbCategories.SelectedIndex = 0
Clear-Log
Write-LogLine "SysAdmin Toolkit v5.0 готовий. F1 — довідка." -Color "#89b4fa"

$window.Add_Closed({ $script:trayIcon.Dispose(); $script:statusTimer.Stop() })
$window.ShowDialog() | Out-Null
