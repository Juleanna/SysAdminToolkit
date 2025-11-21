Add-Type -AssemblyName PresentationFramework

# Чистый UTF-8, без сторонних кодировок

$base        = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $base "Scripts\Utils\ToolkitCommon.psm1") -Force

$scriptsRoot = Join-Path $base "Scripts"
$logsRoot    = Join-Path $base "Logs"

if (-not (Test-Path $logsRoot)) {
    New-Item -ItemType Directory -Path $logsRoot | Out-Null
}

$logFile = Join-Path $logsRoot "Toolkit.log"
$cfg = Get-ToolkitConfig

function Write-ToolkitLog {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts`t$Message"
    Add-Content -Path $logFile -Value $line
}

$global:Actions = @(
    # ===== Инвентаризация =====
    [PSCustomObject]@{ Category="Инвентаризация"; Name="Инвентаризация ПК"; Script="Inventory\Get-PC-Inventory.ps1" }
    [PSCustomObject]@{ Category="Инвентаризация"; Name="Список установленного ПО"; Script="Inventory\Get-InstalledSoftware.ps1" }
    [PSCustomObject]@{ Category="Инвентаризация"; Name="Последняя инвентаризация в Telegram"; Script="Telegram\Send-LastInventoryToTG.ps1" }

    # ===== Мониторинг =====
    [PSCustomObject]@{ Category="Мониторинг"; Name="Проверка производительности"; Script="Monitoring\Check-Performance.ps1" }
    [PSCustomObject]@{ Category="Мониторинг"; Name="Экспорт событий"; Script="Monitoring\Export-EventLogs.ps1" }

    # ===== Бэкапы =====
    [PSCustomObject]@{ Category="Бэкапы"; Name="Резервная копия папки"; Script="Backup\Backup-Folder.ps1" }
    [PSCustomObject]@{ Category="Бэкапы"; Name="Бэкап профилей пользователей"; Script="Backup\Backup-UserProfiles.ps1" }

    # ===== Сеть =====
    [PSCustomObject]@{ Category="Сеть"; Name="Проверка сети"; Script="Network\Test-Network.ps1" }
    [PSCustomObject]@{ Category="Сеть"; Name="Сканирование LAN"; Script="Network\Scan-LAN.ps1" }
    [PSCustomObject]@{ Category="Сеть"; Name="Восстановление сети"; Script="Recovery\Repair-Network.ps1" }

    # ===== Принтеры =====
    [PSCustomObject]@{ Category="Принтеры"; Name="Добавить сетевой принтер"; Script="Printers\Add-NetworkPrinter.ps1" }
    [PSCustomObject]@{ Category="Принтеры"; Name="Удалить принтер"; Script="Printers\Remove-Printer.ps1" }
    [PSCustomObject]@{ Category="Принтеры"; Name="Перезапуск службы печати"; Script="Printers\Restart-Spooler.ps1" }

    # ===== Профили =====
    [PSCustomObject]@{ Category="Профили"; Name="Удалить старые профили"; Script="Profiles\Delete-OldProfiles.ps1" }
    [PSCustomObject]@{ Category="Профили"; Name="Очистить профиль пользователя"; Script="Profiles\Clean-UserProfile.ps1" }

    # ===== Массовые операции =====
    [PSCustomObject]@{ Category="Массовые операции"; Name="Перезагрузка списка ПК"; Script="Mass\Restart-Computers.ps1" }

    # ===== Безопасность =====
    [PSCustomObject]@{ Category="Безопасность"; Name="Вкл/выкл USB-накопители"; Script="Security\Toggle-USBStorage.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="Локальные администраторы"; Script="Security\List-LocalAdmins.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="Быстрая проверка на малварь"; Script="Security\Quick-Malware-Check.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="Статус брандмауэра (вкл/выкл)"; Script="Security\Firewall-Profile.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="RDP + NLA (вкл/выкл)"; Script="Security\Toggle-RDP.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="Политика паролей (отчёт)"; Script="Security\PasswordPolicy-Report.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="Быстрая проверка Defender"; Script="Security\Defender-QuickScan.ps1" }
    [PSCustomObject]@{ Category="Безопасность"; Name="BitLocker статус"; Script="Security\BitLocker-Status.ps1" }

    # ===== Восстановление =====
    [PSCustomObject]@{ Category="Восстановление"; Name="Проверка Windows (SFC + DISM)"; Script="Recovery\Repair-Windows.ps1" }

    # ===== Утилиты =====
    [PSCustomObject]@{ Category="Утилиты"; Name="Очистить временные файлы"; Script="Utils\Clean-Temp.ps1" }
    [PSCustomObject]@{ Category="Утилиты"; Name="Сбор логов"; Script="Utils\Collect-Logs.ps1" }

    # ===== Telegram =====
    [PSCustomObject]@{ Category="Telegram"; Name="Тестовое сообщение"; Script="Telegram\Test-TGMessage.ps1" }

    # ===== Удалённая помощь =====
    [PSCustomObject]@{ Category="Удалённая помощь"; Name="Процессы на удалённом ПК"; Script="RemoteHelp\Get-RemoteProcesses.ps1" }
    [PSCustomObject]@{ Category="Удалённая помощь"; Name="Завершить процесс на удалённом ПК"; Script="RemoteHelp\Kill-RemoteProcess.ps1" }
    [PSCustomObject]@{ Category="Удалённая помощь"; Name="Окно с сообщением"; Script="RemoteHelp\Popup-Message.ps1" }
    [PSCustomObject]@{ Category="Удалённая помощь"; Name="Сбор логов с удалённого ПК"; Script="RemoteHelp\Collect-RemoteLogs.ps1" }
    [PSCustomObject]@{ Category="Удалённая помощь"; Name="Выполнить команду на удалённом ПК"; Script="RemoteHelp\Run-RemoteCommand.ps1" }
)

$categories = $Actions | Select-Object -ExpandProperty Category -Unique | Sort-Object

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="SysAdmin Toolkit v5.0 — $($cfg.CompanyName)" Height="640" Width="980" WindowStartupLocation="CenterScreen">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="2*"/>
      <RowDefinition Height="1*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="2*"/>
      <ColumnDefinition Width="3*"/>
    </Grid.ColumnDefinitions>

    <StackPanel Grid.Row="0" Grid.ColumnSpan="2" Margin="0,0,0,10">
      <TextBlock Text="SysAdmin Toolkit v5.0 — Общие настройки для SysAdminToolkit v5.0" FontSize="18" FontWeight="Bold"/>
      <TextBlock Text="Компания: $($cfg.CompanyName)" FontSize="12" Foreground="Gray"/>
    </StackPanel>

    <GroupBox Grid.Row="1" Grid.Column="0" Header="Категории" Margin="0,0,10,10">
      <Grid>
        <ListBox Name="lbCategories"/>
      </Grid>
    </GroupBox>

    <GroupBox Grid.Row="1" Grid.Column="1" Header="Действия" Margin="0,0,0,10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListBox Name="lbActions" Grid.Row="0" DisplayMemberPath="Name"/>
        <StackPanel Grid.Row="1" Orientation="Vertical" Margin="0,5,0,0">
          <TextBlock Text="Параметры (ключ=значение;ключ2=значение2) — опционально" FontSize="11" />
          <TextBox Name="txtParams" Height="26"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,5,0,0">
          <Button Name="btnRun" Content="Запустить" Height="30" Width="120" Margin="0,0,5,0"/>
          <Button Name="btnCancel" Content="Отмена" Height="30" Width="120" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </GroupBox>

    <GroupBox Grid.Row="2" Grid.ColumnSpan="2" Header="Лог / вывод">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
          <TextBlock Text="Прогресс:" VerticalAlignment="Center" Margin="0,0,5,0"/>
          <ProgressBar Name="pbStatus" Minimum="0" Maximum="100" Height="15" Width="300"/>
          <TextBlock Name="lblProgress" Margin="5,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBox Name="txtLog" Grid.Row="1" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"/>
      </Grid>
    </GroupBox>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$lbCategories = $window.FindName("lbCategories")
$lbActions    = $window.FindName("lbActions")
$btnRun       = $window.FindName("btnRun")
$btnCancel    = $window.FindName("btnCancel")
$txtLog       = $window.FindName("txtLog")
$txtParams    = $window.FindName("txtParams")
$pbStatus     = $window.FindName("pbStatus")
$lblProgress  = $window.FindName("lblProgress")

$lbCategories.ItemsSource = $categories

$lbCategories.Add_SelectionChanged({
    $cat = $lbCategories.SelectedItem
    if ($null -eq $cat) { return }

    $items = @($Actions | Where-Object { $_.Category -eq $cat })
    $lbActions.ItemsSource = $items
})

$script:currentJob = $null
$script:jobTimer = New-Object Windows.Threading.DispatcherTimer
$script:jobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:jobTimer.Add_Tick({
    if ($null -eq $script:currentJob) { $script:jobTimer.Stop(); return }

    try {
        $chunk = Receive-Job -Job $script:currentJob -Keep -ErrorAction SilentlyContinue
        if ($chunk) {
            foreach ($line in $chunk) {
                if ($line -match '^PROGRESS:\s*(\d+)') {
                    $val = [int]$Matches[1]
                    $pbStatus.Value = [math]::Min(100,[math]::Max(0,$val))
                    $lblProgress.Text = "$val%"
                    continue
                }
                $txtLog.Text += $line
            }
        }
    } catch {}

    if ($script:currentJob.State -in @("Completed","Failed","Stopped")) {
        $script:jobTimer.Stop()
        $result = Receive-Job -Job $script:currentJob -Keep
        $state = $script:currentJob.State
        Remove-Job $script:currentJob -Force -ErrorAction SilentlyContinue
        $script:currentJob = $null
        $btnRun.IsEnabled = $true
        $btnCancel.IsEnabled = $false
        $pbStatus.Value = 0
        $lblProgress.Text = ""

        if ($state -eq "Stopped") {
            $txtLog.Text += "`r`nВыполнение отменено пользователем."
            Write-ToolkitLog "Отмена выполнения"
            return
        }

        if ($result -and $result.Success) {
            $txtLog.Text = $result.Output
            Write-ToolkitLog "Успешно: $($result.DisplayName)"
        } else {
            $err = if ($result) { $result.ErrorMessage } else { "Неизвестная ошибка" }
            $txtLog.Text += "`r`nОшибка: $err"
            Write-ToolkitLog "Ошибка: $err"
        }
    }
})

function Invoke-ToolkitScript {
    param(
        [string]$RelativePath,
        [string]$DisplayName,
        [hashtable]$ArgsHashtable
    )

    if ($script:currentJob) {
        $txtLog.Text = "Уже выполняется другая задача. Дождитесь завершения или нажмите Отмена."
        return
    }

    $scriptPath = Join-Path $scriptsRoot $RelativePath

    if (-not (Test-Path $scriptPath)) {
        $msg = "Файл не найден: $scriptPath"
        $txtLog.Text = $msg
        Write-ToolkitLog $msg
        return
    }

    $txtLog.Text = "Запуск: $DisplayName`r`n$scriptPath`r`n..."
    Write-ToolkitLog "Старт: $DisplayName ($scriptPath)"
    $btnRun.IsEnabled = $false
    $btnCancel.IsEnabled = $true
    $pbStatus.Value = 0
    $lblProgress.Text = ""

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

$btnRun.Add_Click({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $args = ConvertFrom-ParamString $txtParams.Text
    Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable $args
})

$btnCancel.Add_Click({
    if ($script:currentJob) {
        Stop-Job -Job $script:currentJob -Force -ErrorAction SilentlyContinue
    }
})

$lbActions.Add_MouseDoubleClick({
    $sel = $lbActions.SelectedItem
    if ($null -eq $sel) { return }
    $args = ConvertFrom-ParamString $txtParams.Text
    Invoke-ToolkitScript -RelativePath $sel.Script -DisplayName $sel.Name -ArgsHashtable $args
})

$lbCategories.SelectedIndex = 0

$window.ShowDialog() | Out-Null
