Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$base        = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $base "Scripts\Utils\ToolkitCommon.psm1") -Force

$scriptsRoot = Join-Path $base "Scripts"
$logsRoot    = Join-Path $base "Logs"
$reportsRoot = Join-Path $base "Reports"

if (-not (Test-Path $logsRoot))    { New-Item -ItemType Directory -Path $logsRoot    | Out-Null }
if (-not (Test-Path $reportsRoot)) { New-Item -ItemType Directory -Path $reportsRoot | Out-Null }

$logFile = Join-Path $logsRoot "Toolkit.log"
$cfg = Get-ToolkitConfig

# ============================================================
#  Дії (Actions) — повний список
# ============================================================

$global:Actions = @(
    # ===== Інвентаризація =====
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Інвентаризація ПК"; Script="Inventory\Get-PC-Inventory.ps1"; Desc="Збір повної інформації про конфігурацію ПК (CPU, RAM, диски, мережа)" }
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Список встановленого ПЗ"; Script="Inventory\Get-InstalledSoftware.ps1"; Desc="Експорт списку всіх встановлених програм у CSV" }
    [PSCustomObject]@{ Category="Інвентаризація"; Name="Надіслати інвентаризацію в Telegram"; Script="Telegram\Send-LastInventoryToTG.ps1"; Desc="Відправити останній файл інвентаризації у Telegram-чат" }

    # ===== Моніторинг =====
    [PSCustomObject]@{ Category="Моніторинг"; Name="Перевірка продуктивності"; Script="Monitoring\Check-Performance.ps1"; Desc="CPU, RAM, диски — поточне навантаження та стан" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Експорт журналів"; Script="Monitoring\Export-EventLogs.ps1"; Desc="Збереження системних та безпекових журналів у файл" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Аптайм критичних сервісів"; Script="Monitoring\Check-ServiceUptime.ps1"; Desc="Статус та час роботи критичних сервісів з конфігурації" }
    [PSCustomObject]@{ Category="Моніторинг"; Name="Перевірка дискового простору"; Script="Monitoring\Check-DiskSpace.ps1"; Desc="Швидка перевірка вільного місця на дисках з порогами попередження" }

    # ===== Сервіси =====
    [PSCustomObject]@{ Category="Сервіси"; Name="Монітор сервісів"; Script="Services\Service-Monitor.ps1"; Desc="Дашборд стану критичних Windows-сервісів" }
    [PSCustomObject]@{ Category="Сервіси"; Name="Перезапуск сервісу"; Script="Services\Service-Restart.ps1"; Desc="Перезапуск сервісу з обробкою залежностей (ServiceName=ім'я)" }
    [PSCustomObject]@{ Category="Сервіси"; Name="Автовідновлення сервісу"; Script="Services\Service-AutoRecover.ps1"; Desc="Налаштування автоматичного перезапуску при збої (ServiceName=ім'я;Mode=Status/Enable/Disable)" }

    # ===== Диски =====
    [PSCustomObject]@{ Category="Диски"; Name="Здоров'я дисків (SMART)"; Script="Disks\Disk-Health.ps1"; Desc="SMART-статус фізичних дисків" }
    [PSCustomObject]@{ Category="Диски"; Name="Звіт дискового простору"; Script="Disks\Disk-SpaceReport.ps1"; Desc="Детальний звіт використання дисків з HTML-експортом" }
    [PSCustomObject]@{ Category="Диски"; Name="Очищення старих файлів"; Script="Disks\Cleanup-OldFiles.ps1"; Desc="Видалення файлів старше N днів (Path=шлях;DaysOld=30)" }
    [PSCustomObject]@{ Category="Диски"; Name="Квоти профілів (розміри)"; Script="Disks\Disk-QuotaReport.ps1"; Desc="Розмір кожного профілю користувача на диску" }

    # ===== Сертифікати =====
    [PSCustomObject]@{ Category="Сертифікати"; Name="Перевірка терміну сертифікатів"; Script="Certificates\Cert-ExpiryCheck.ps1"; Desc="Пошук сертифікатів, що скоро спливають" }
    [PSCustomObject]@{ Category="Сертифікати"; Name="Встановлення сертифікату"; Script="Certificates\Cert-Install.ps1"; Desc="Імпорт сертифікату у сховище (CertPath=шлях)" }

    # ===== Заплановані завдання =====
    [PSCustomObject]@{ Category="Заплановані завдання"; Name="Звіт завдань планувальника"; Script="ScheduledTasks\ScheduledTask-Report.ps1"; Desc="Список усіх запланованих завдань зі статусом" }
    [PSCustomObject]@{ Category="Заплановані завдання"; Name="Створити заплановане завдання"; Script="ScheduledTasks\ScheduledTask-Create.ps1"; Desc="Створення нового завдання в планувальнику" }

    # ===== Бекапи =====
    [PSCustomObject]@{ Category="Бекапи"; Name="Резервна копія папки"; Script="Backup\Backup-Folder.ps1"; Desc="Архівація вказаної папки у ZIP" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап профілів користувачів"; Script="Backup\Backup-UserProfiles.ps1"; Desc="Резервне копіювання профілів робочих станцій" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап запланованих завдань"; Script="Backup\Backup-ScheduledTask.ps1"; Desc="Експорт усіх завдань планувальника у XML" }
    [PSCustomObject]@{ Category="Бекапи"; Name="Бекап групових політик"; Script="Backup\Backup-GPO.ps1"; Desc="Резервне копіювання GPO (потрібен RSAT)" }

    # ===== Мережа =====
    [PSCustomObject]@{ Category="Мережа"; Name="Перевірка мережі"; Script="Network\Test-Network.ps1"; Desc="Базова діагностика мережевого підключення" }
    [PSCustomObject]@{ Category="Мережа"; Name="Сканування LAN"; Script="Network\Scan-LAN.ps1"; Desc="Пошук активних хостів у підмережі (паралельно)" }
    [PSCustomObject]@{ Category="Мережа"; Name="Відновлення мережі"; Script="Recovery\Repair-Network.ps1"; Desc="Скидання мережевих налаштувань (DNS, Winsock, IP)" }
    [PSCustomObject]@{ Category="Мережа"; Name="Тест портів"; Script="Network\Test-Ports.ps1"; Desc="Перевірка TCP-портів на хості (ComputerName=ім'я;Ports=80,443,3389)" }
    [PSCustomObject]@{ Category="Мережа"; Name="DNS-записи"; Script="Network\Get-DNSRecords.ps1"; Desc="Запит DNS-записів домену (DomainName=ім'я;RecordType=A/MX/NS)" }

    # ===== Принтери =====
    [PSCustomObject]@{ Category="Принтери"; Name="Додати мережевий принтер"; Script="Printers\Add-NetworkPrinter.ps1"; Desc="Підключення мережевого принтера" }
    [PSCustomObject]@{ Category="Принтери"; Name="Видалити принтер"; Script="Printers\Remove-Printer.ps1"; Desc="Видалення встановленого принтера" }
    [PSCustomObject]@{ Category="Принтери"; Name="Перезапуск служби друку"; Script="Printers\Restart-Spooler.ps1"; Desc="Перезапуск Print Spooler" }

    # ===== Профілі =====
    [PSCustomObject]@{ Category="Профілі"; Name="Видалити старі профілі"; Script="Profiles\Delete-OldProfiles.ps1"; Desc="Видалення профілів, не використаних понад N днів" }
    [PSCustomObject]@{ Category="Профілі"; Name="Очищення профілю користувача"; Script="Profiles\Clean-UserProfile.ps1"; Desc="Очищення кешу та тимчасових файлів профілю" }

    # ===== Масові операції =====
    [PSCustomObject]@{ Category="Масові операції"; Name="Перезавантажити групу ПК"; Script="Mass\Restart-Computers.ps1"; Desc="Перезавантаження комп'ютерів зі списку" }
    [PSCustomObject]@{ Category="Масові операції"; Name="Виконати на групі хостів"; Script="Mass\Run-OnMultiple.ps1"; Desc="Запуск скрипту на декількох ПК з Hosts.json (ScriptPath=шлях)" }

    # ===== Безпека =====
    [PSCustomObject]@{ Category="Безпека"; Name="Вкл/Викл USB-накопичувачі"; Script="Security\Toggle-USBStorage.ps1"; Desc="Блокування або розблокування USB-носіїв через реєстр" }
    [PSCustomObject]@{ Category="Безпека"; Name="Перегляд адміністраторів"; Script="Security\List-LocalAdmins.ps1"; Desc="Список членів групи Адміністратори" }
    [PSCustomObject]@{ Category="Безпека"; Name="Швидка перевірка на загрози"; Script="Security\Quick-Malware-Check.ps1"; Desc="Підозрілі процеси, Defender, автозапуск" }
    [PSCustomObject]@{ Category="Безпека"; Name="Профіль брандмауера (Вкл/Викл)"; Script="Security\Firewall-Profile.ps1"; Desc="Керування Windows Firewall (Mode=Status/Enable/Disable/Toggle)" }
    [PSCustomObject]@{ Category="Безпека"; Name="RDP + NLA (Вкл/Викл)"; Script="Security\Toggle-RDP.ps1"; Desc="Увімкнення/вимкнення Remote Desktop з NLA" }
    [PSCustomObject]@{ Category="Безпека"; Name="Політика паролів (звіт)"; Script="Security\PasswordPolicy-Report.ps1"; Desc="Перегляд поточних вимог до паролів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Швидке сканування Defender"; Script="Security\Defender-QuickScan.ps1"; Desc="Запуск швидкого антивірусного сканування" }
    [PSCustomObject]@{ Category="Безпека"; Name="BitLocker статус"; Script="Security\BitLocker-Status.ps1"; Desc="Стан шифрування дисків BitLocker" }
    [PSCustomObject]@{ Category="Безпека"; Name="Локальні користувачі (звіт)"; Script="Security\LocalUsers-Report.ps1"; Desc="Список усіх локальних облікових записів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Локальні користувачі (керування)"; Script="Security\LocalUser-Manage.ps1"; Desc="Створити/Вкл/Викл/Скинути пароль локального користувача" }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит подій безпеки"; Script="Security\Audit-Report.ps1"; Desc="Звіт аудиту подій безпеки з Event Log" }
    [PSCustomObject]@{ Category="Безпека"; Name="WinRM/SMB/NTLM (Захист)"; Script="Security\RemoteAccess-Hardening.ps1"; Desc="Перевірка та посилення віддаленого доступу" }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит-політики (застосувати)"; Script="Security\AuditPolicy-Apply.ps1"; Desc="Налаштування політик аудиту Windows" }
    [PSCustomObject]@{ Category="Безпека"; Name="LSA/SmartScreen/Кеш логінів"; Script="Security\AccountProtection.ps1"; Desc="Захист облікових записів: LSA PPL, SmartScreen" }
    [PSCustomObject]@{ Category="Безпека"; Name="Автозапуск/Сервіси (звіт)"; Script="Security\Autoruns-Report.ps1"; Desc="Огляд програм автозапуску та сервісів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Оновлення й сигнатури"; Script="Security\SecurityUpdates.ps1"; Desc="Перевірка та встановлення оновлень безпеки" }
    [PSCustomObject]@{ Category="Безпека"; Name="Аудит спільних папок"; Script="Security\Audit-SharedFolders.ps1"; Desc="Перелік усіх мережевих спільних ресурсів та прав" }
    [PSCustomObject]@{ Category="Безпека"; Name="Відкриті порти"; Script="Security\Check-OpenPorts.ps1"; Desc="Список відкритих TCP/UDP портів та процесів" }
    [PSCustomObject]@{ Category="Безпека"; Name="Експорт Security Baseline"; Script="Security\Export-SecurityBaseline.ps1"; Desc="Знімок безпекових налаштувань системи" }

    # ===== Відновлення =====
    [PSCustomObject]@{ Category="Відновлення"; Name="Ремонт Windows (SFC + DISM)"; Script="Recovery\Repair-Windows.ps1"; Desc="Перевірка та відновлення системних файлів" }

    # ===== Утиліти =====
    [PSCustomObject]@{ Category="Утиліти"; Name="Очищення тимчасових файлів"; Script="Utils\Clean-Temp.ps1"; Desc="Видалення TEMP, кешу та тимчасових файлів" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Збір логів"; Script="Utils\Collect-Logs.ps1"; Desc="Збір системних та тулкіт-логів у архів" }
    [PSCustomObject]@{ Category="Утиліти"; Name="Інформація про систему"; Script="Utils\System-Info.ps1"; Desc="Повний огляд системи: ОС, CPU, RAM, мережа, аптайм" }

    # ===== Telegram =====
    [PSCustomObject]@{ Category="Telegram"; Name="Тестове повідомлення"; Script="Telegram\Test-TGMessage.ps1"; Desc="Надсилання тестового повідомлення у Telegram" }
    [PSCustomObject]@{ Category="Telegram"; Name="Відправити сповіщення"; Script="Telegram\Send-TGAlert.ps1"; Desc="Відправка форматованого алерту (Level=Info/Warning/Critical;Title=текст;Message=текст)" }

    # ===== Віддалена допомога =====
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Процеси на віддаленому ПК"; Script="RemoteHelp\Get-RemoteProcesses.ps1"; Desc="Перегляд процесів на віддаленому комп'ютері" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Завершити процес на віддаленому ПК"; Script="RemoteHelp\Kill-RemoteProcess.ps1"; Desc="Примусове завершення процесу на віддаленому ПК" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Вікно з повідомленням"; Script="RemoteHelp\Popup-Message.ps1"; Desc="Показати повідомлення на екрані віддаленого ПК" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Збір логів з віддаленого ПК"; Script="RemoteHelp\Collect-RemoteLogs.ps1"; Desc="Збір та архівування логів з віддаленого ПК" }
    [PSCustomObject]@{ Category="Віддалена допомога"; Name="Виконати команду на віддаленому ПК"; Script="RemoteHelp\Run-RemoteCommand.ps1"; Desc="Запуск PowerShell-команди на віддаленому ПК" }
)

$categories = $Actions | Select-Object -ExpandProperty Category -Unique | Sort-Object

# ============================================================
#  Історія виконання
# ============================================================
$script:ExecutionHistory = [System.Collections.ArrayList]::new()

# ============================================================
#  WPF XAML — Dark Theme
# ============================================================

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SysAdmin Toolkit v5.0 — $($cfg.CompanyName)" Height="750" Width="1100"
        WindowStartupLocation="CenterScreen"
        Background="#1e1e2e" Foreground="#cdd6f4">
  <Window.Resources>
    <Style TargetType="GroupBox">
      <Setter Property="Foreground" Value="#cba6f7"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="ListBox">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#cdd6f4"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#cdd6f4"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
      <Setter Property="CaretBrush" Value="#cdd6f4"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#45475a"/>
      <Setter Property="Foreground" Value="#cdd6f4"/>
      <Setter Property="BorderBrush" Value="#585b70"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TabControl">
      <Setter Property="Background" Value="#1e1e2e"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="#a6adc8"/>
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
      <Setter Property="Padding" Value="10,4"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Foreground" Value="#cba6f7"/>
          <Setter Property="Background" Value="#45475a"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#89b4fa"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#cdd6f4"/>
      <Setter Property="BorderBrush" Value="#45475a"/>
      <Setter Property="RowBackground" Value="#313244"/>
      <Setter Property="AlternatingRowBackground" Value="#3b3d52"/>
      <Setter Property="GridLinesVisibility" Value="None"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
    </Style>
  </Window.Resources>

  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="2*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="1.2*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="220"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Grid.ColumnSpan="2" Margin="0,0,0,8">
      <TextBlock Text="SysAdmin Toolkit v5.0" FontSize="20" FontWeight="Bold" Foreground="#89b4fa"/>
      <TextBlock Text="Панель керування — $($cfg.CompanyName) | $($env:COMPUTERNAME)" FontSize="11" Foreground="#6c7086"/>
    </StackPanel>

    <!-- Search -->
    <Grid Grid.Row="1" Grid.ColumnSpan="2" Margin="0,0,0,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Text="Пошук:" Foreground="#a6adc8" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox Name="txtSearch" Grid.Column="1" Height="26" ToolTip="Фільтр дій за назвою або описом"/>
    </Grid>

    <!-- Categories -->
    <GroupBox Grid.Row="2" Grid.Column="0" Header="Категорії" Margin="0,0,8,8">
      <ListBox Name="lbCategories" FontSize="13"/>
    </GroupBox>

    <!-- Actions -->
    <GroupBox Grid.Row="2" Grid.Column="1" Header="Операції" Margin="0,0,0,8">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListBox Name="lbActions" Grid.Row="0" DisplayMemberPath="Name" FontSize="13"/>
        <TextBlock Name="lblDesc" Grid.Row="1" Foreground="#a6adc8" FontSize="11" TextWrapping="Wrap" Margin="4,4,4,0" MinHeight="18"/>
        <StackPanel Grid.Row="2" Orientation="Vertical" Margin="0,5,0,0">
          <TextBlock Text="Параметри (Ключ=Значення;Ключ2=Значення2) — необов'язково" FontSize="11" Foreground="#6c7086"/>
          <TextBox Name="txtParams" Height="26"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,6,0,0">
          <Button Name="btnRun" Content="Виконати (F5)" Height="30" Width="130" Margin="0,0,5,0"/>
          <Button Name="btnCancel" Content="Скасувати (Esc)" Height="30" Width="130" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </GroupBox>

    <!-- Progress bar -->
    <StackPanel Grid.Row="3" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,0,0,4">
      <TextBlock Text="Прогрес:" Foreground="#a6adc8" VerticalAlignment="Center" Margin="0,0,5,0"/>
      <ProgressBar Name="pbStatus" Minimum="0" Maximum="100" Height="15" Width="300"/>
      <TextBlock Name="lblProgress" Foreground="#a6e3a1" Margin="8,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>

    <!-- Tabs: Log / History -->
    <TabControl Grid.Row="4" Grid.ColumnSpan="2">
      <TabItem Header="Лог / Вивід">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <RichTextBox Name="rtbLog" Grid.Row="0"
                       Background="#181825" Foreground="#cdd6f4" BorderBrush="#45475a"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                       IsReadOnly="True" FontFamily="Consolas" FontSize="12">
            <RichTextBox.Document>
              <FlowDocument PageWidth="5000">
                <Paragraph Name="logParagraph"/>
              </FlowDocument>
            </RichTextBox.Document>
          </RichTextBox>
          <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,4,0,0">
            <Button Name="btnExportLog" Content="Експорт логу" Height="26" Width="120" Margin="0,0,5,0"/>
            <Button Name="btnClearLog" Content="Очистити" Height="26" Width="100"/>
          </StackPanel>
        </Grid>
      </TabItem>
      <TabItem Header="Історія виконання">
        <DataGrid Name="dgHistory" AutoGenerateColumns="False" IsReadOnly="True"
                  CanUserAddRows="False" CanUserDeleteRows="False"
                  ColumnHeaderHeight="28" RowHeight="24">
          <DataGrid.ColumnHeaderStyle>
            <Style TargetType="DataGridColumnHeader">
              <Setter Property="Background" Value="#45475a"/>
              <Setter Property="Foreground" Value="#cba6f7"/>
              <Setter Property="Padding" Value="6,2"/>
              <Setter Property="BorderBrush" Value="#585b70"/>
              <Setter Property="BorderThickness" Value="0,0,1,1"/>
            </Style>
          </DataGrid.ColumnHeaderStyle>
          <DataGrid.Columns>
            <DataGridTextColumn Header="Час" Binding="{Binding Time}" Width="140"/>
            <DataGridTextColumn Header="Дія" Binding="{Binding Action}" Width="*"/>
            <DataGridTextColumn Header="Статус" Binding="{Binding Status}" Width="100"/>
            <DataGridTextColumn Header="Тривалість" Binding="{Binding Duration}" Width="100"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
    </TabControl>
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
$rtbLog       = $window.FindName("rtbLog")
$txtParams    = $window.FindName("txtParams")
$txtSearch    = $window.FindName("txtSearch")
$pbStatus     = $window.FindName("pbStatus")
$lblProgress  = $window.FindName("lblProgress")
$lblDesc      = $window.FindName("lblDesc")
$btnExportLog = $window.FindName("btnExportLog")
$btnClearLog  = $window.FindName("btnClearLog")
$dgHistory    = $window.FindName("dgHistory")

$lbCategories.ItemsSource = $categories

# ============================================================
#  Функції логування у RichTextBox
# ============================================================

function Write-LogLine {
    param(
        [string]$Text,
        [string]$Color = "#cdd6f4"
    )
    $doc = $rtbLog.Document
    $para = $doc.Blocks.LastBlock
    if ($null -eq $para) {
        $para = New-Object System.Windows.Documents.Paragraph
        $doc.Blocks.Add($para)
    }
    $run = New-Object System.Windows.Documents.Run($Text + "`r`n")
    try {
        $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    } catch {
        $run.Foreground = [System.Windows.Media.Brushes]::White
    }
    $para.Inlines.Add($run)
    $rtbLog.ScrollToEnd()
}

function Clear-Log {
    $rtbLog.Document.Blocks.Clear()
    $para = New-Object System.Windows.Documents.Paragraph
    $rtbLog.Document.Blocks.Add($para)
}

function Get-LogText {
    $range = New-Object System.Windows.Documents.TextRange($rtbLog.Document.ContentStart, $rtbLog.Document.ContentEnd)
    return $range.Text
}

# ============================================================
#  Фільтрація категорій / дій
# ============================================================

function Update-ActionsList {
    $search = $txtSearch.Text.Trim().ToLower()
    $cat = $lbCategories.SelectedItem

    if ([string]::IsNullOrEmpty($search)) {
        if ($null -eq $cat) {
            $lbActions.ItemsSource = @()
        } else {
            $items = @($Actions | Where-Object { $_.Category -eq $cat })
            $lbActions.ItemsSource = $items
        }
    } else {
        $items = @($Actions | Where-Object {
            $_.Name.ToLower().Contains($search) -or $_.Desc.ToLower().Contains($search)
        })
        $lbActions.ItemsSource = $items
    }
    $lblDesc.Text = ""
}

$lbCategories.Add_SelectionChanged({ Update-ActionsList })

$txtSearch.Add_TextChanged({
    $search = $txtSearch.Text.Trim()
    if ([string]::IsNullOrEmpty($search)) {
        Update-ActionsList
    } else {
        # Під час пошуку знімаємо вибір категорії
        $lbCategories.SelectedIndex = -1
        Update-ActionsList
    }
})

# Показ опису обраної дії
$lbActions.Add_SelectionChanged({
    $sel = $lbActions.SelectedItem
    if ($null -ne $sel -and $sel.Desc) {
        $lblDesc.Text = $sel.Desc
    } else {
        $lblDesc.Text = ""
    }
})

# ============================================================
#  Виконання скриптів (Job)
# ============================================================

$script:currentJob = $null
$script:lastOutputIndex = 0
$script:jobStartTime = $null
$script:currentActionName = ""

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
                if ($lineStr -match '^PROGRESS:\s*(\d+)') {
                    $val = [int]$Matches[1]
                    $pbStatus.Value = [math]::Min(100,[math]::Max(0,$val))
                    $lblProgress.Text = "$val%"
                    continue
                }
                # Кольорове виділення
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
        $script:currentJob = $null
        $script:lastOutputIndex = 0
        $btnRun.IsEnabled = $true
        $btnCancel.IsEnabled = $false
        $pbStatus.Value = 0
        $lblProgress.Text = ""

        $duration = ""
        if ($script:jobStartTime) {
            $elapsed = (Get-Date) - $script:jobStartTime
            $duration = "{0:mm\:ss}" -f $elapsed
        }

        if ($state -eq "Stopped") {
            Write-LogLine "Виконання скасовано користувачем." -Color "#fab387"
            Write-TkLog "Скасовано: $($script:currentActionName)" -Level WARN
            [void]$script:ExecutionHistory.Add([PSCustomObject]@{
                Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); Action = $script:currentActionName; Status = "Скасовано"; Duration = $duration
            })
            $dgHistory.ItemsSource = $null
            $dgHistory.ItemsSource = $script:ExecutionHistory
            return
        }

        if ($result -and $result.Success) {
            Write-LogLine "--- Завершено успішно ---" -Color "#a6e3a1"
            Write-TkLog "Успішно: $($script:currentActionName)" -Level INFO
            [void]$script:ExecutionHistory.Add([PSCustomObject]@{
                Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); Action = $script:currentActionName; Status = "Успішно"; Duration = $duration
            })
        } else {
            $err = if ($result) { $result.ErrorMessage } else { "Невідома помилка" }
            Write-LogLine "Помилка: $err" -Color "#f38ba8"
            Write-TkLog "Помилка: $($script:currentActionName) — $err" -Level ERROR
            [void]$script:ExecutionHistory.Add([PSCustomObject]@{
                Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); Action = $script:currentActionName; Status = "Помилка"; Duration = $duration
            })
        }
        $dgHistory.ItemsSource = $null
        $dgHistory.ItemsSource = $script:ExecutionHistory
    }
})

function Invoke-ToolkitScript {
    param(
        [string]$RelativePath,
        [string]$DisplayName,
        [hashtable]$ArgsHashtable
    )

    if ($script:currentJob) {
        Write-LogLine "Вже виконується інший скрипт. Зачекайте або натисніть Скасувати." -Color "#fab387"
        return
    }

    $scriptPath = Join-Path $scriptsRoot $RelativePath

    if (-not (Test-Path $scriptPath)) {
        $msg = "Файл не знайдено: $scriptPath"
        Write-LogLine $msg -Color "#f38ba8"
        Write-TkLog $msg -Level ERROR
        return
    }

    Clear-Log
    Write-LogLine "Запуск: $DisplayName" -Color "#89b4fa"
    Write-LogLine $scriptPath -Color "#6c7086"
    Write-LogLine "---" -Color "#45475a"
    Write-TkLog "Старт: $DisplayName ($scriptPath)" -Level INFO
    $btnRun.IsEnabled = $false
    $btnCancel.IsEnabled = $true
    $pbStatus.Value = 0
    $lblProgress.Text = ""
    $script:lastOutputIndex = 0
    $script:jobStartTime = Get-Date
    $script:currentActionName = $DisplayName

    $argArray = @()
    foreach ($k in $ArgsHashtable.Keys) {
        $argArray += ('-' + $k)
        $argArray += $ArgsHashtable[$k]
    }

    $script:currentJob = Start-Job -ScriptBlock {
        param($ScriptPath,$DisplayName,$ArgArray,$WorkingDirectory)
        Set-Location $WorkingDirectory
        $result = [pscustomobject]@{ Success=$false; Output=""; ErrorMessage=""; DisplayName=$DisplayName }
        try {
            $output = & $ScriptPath @ArgArray *>&1 | Out-String
            $result.Success = $true
            $result.Output = $output
        } catch {
            $result.ErrorMessage = $_.Exception.Message
        }
        return $result
    } -ArgumentList $scriptPath,$DisplayName,$argArray,$base

    $script:jobTimer.Start()
}

# ============================================================
#  Обробники подій кнопок
# ============================================================

$btnRun.Add_Click({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $scriptParams = ConvertFrom-ParamString $txtParams.Text
    Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable $scriptParams
})

$btnCancel.Add_Click({
    if ($script:currentJob) {
        Stop-Job -Job $script:currentJob -Force -ErrorAction SilentlyContinue
    }
})

$lbActions.Add_MouseDoubleClick({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $scriptParams = ConvertFrom-ParamString $txtParams.Text
    Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable $scriptParams
})

# ===== Експорт логу =====
$btnExportLog.Add_Click({
    $text = Get-LogText
    if ([string]::IsNullOrWhiteSpace($text)) {
        Write-LogLine "Лог порожній — нічого експортувати." -Color "#fab387"
        return
    }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportPath = Join-Path $reportsRoot "GUILog_$ts.txt"
    try {
        Set-Content -Path $exportPath -Value $text -Encoding UTF8
        Write-LogLine "Лог експортовано: $exportPath" -Color "#a6e3a1"
    } catch {
        Write-LogLine "Помилка експорту: $($_.Exception.Message)" -Color "#f38ba8"
    }
})

# ===== Очистити лог =====
$btnClearLog.Add_Click({ Clear-Log })

# ============================================================
#  Гарячі клавіші
# ============================================================
$window.Add_KeyDown({
    param($sender, $e)
    switch ($e.Key) {
        'F5' {
            $sel = $lbActions.SelectedItem
            if ($null -ne $sel -and $btnRun.IsEnabled) {
                $scriptParams = ConvertFrom-ParamString $txtParams.Text
                Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable $scriptParams
            }
            $e.Handled = $true
        }
        'Escape' {
            if ($script:currentJob) {
                Stop-Job -Job $script:currentJob -Force -ErrorAction SilentlyContinue
            }
            $e.Handled = $true
        }
        'F1' {
            # Швидка довідка
            Clear-Log
            Write-LogLine "=== SysAdmin Toolkit v5.0 — Довідка ===" -Color "#89b4fa"
            Write-LogLine "" -Color "#cdd6f4"
            Write-LogLine "F5        — Виконати обрану дію" -Color "#a6e3a1"
            Write-LogLine "Escape    — Скасувати виконання" -Color "#fab387"
            Write-LogLine "F1        — Показати цю довідку" -Color "#89b4fa"
            Write-LogLine "" -Color "#cdd6f4"
            Write-LogLine "Пошук — фільтрує дії за назвою та описом" -Color "#cdd6f4"
            Write-LogLine "Подвійний клік — запускає дію" -Color "#cdd6f4"
            Write-LogLine "Параметри — передаються як Ключ=Значення;Ключ2=Значення2" -Color "#cdd6f4"
            Write-LogLine "" -Color "#cdd6f4"
            Write-LogLine "Вкладка 'Історія' — останні запуски" -Color "#cba6f7"
            Write-LogLine "Кнопка 'Експорт' — зберігає лог у файл" -Color "#cba6f7"
            $e.Handled = $true
        }
    }
})

# ============================================================
#  Ініціалізація
# ============================================================

$lbCategories.SelectedIndex = 0
Clear-Log
Write-LogLine "SysAdmin Toolkit v5.0 готовий до роботи." -Color "#89b4fa"
Write-LogLine "Натисніть F1 для довідки." -Color "#6c7086"

$window.ShowDialog() | Out-Null
