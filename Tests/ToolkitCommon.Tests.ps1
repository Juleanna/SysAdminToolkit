#Requires -Modules Pester
<#
    .SYNOPSIS
    Pester v5 тести для модуля ToolkitCommon.psm1
    .DESCRIPTION
    Комплексне покриття тестами всіх експортованих функцій модуля SysAdminToolkit.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Utils\ToolkitCommon.psm1"
    Import-Module $modulePath -Force
}

# ============================================================
#  Get-ToolkitRoot
# ============================================================

Describe "Get-ToolkitRoot" {

    It "Повинна повертати існуючий шлях" {
        $root = Get-ToolkitRoot
        $root | Should -Not -BeNullOrEmpty
        Test-Path $root | Should -BeTrue
    }

    It "Повинна повертати шлях що містить 'SysAdminToolkit'" {
        $root = Get-ToolkitRoot
        $root | Should -Match "SysAdminToolkit"
    }
}

# ============================================================
#  Get-ToolkitConfig
# ============================================================

Describe "Get-ToolkitConfig" {

    It "Повинна повертати об'єкт з властивістю CompanyName" {
        $cfg = Get-ToolkitConfig
        $cfg.PSObject.Properties.Name | Should -Contain "CompanyName"
    }

    It "Повинна мати значення за замовчуванням коли конфіг відсутній" {
        $root = Get-ToolkitRoot
        $configPath = Join-Path $root "Config\ToolkitConfig.json"
        $backupPath = "$configPath.bak"
        $configExists = Test-Path $configPath
        try {
            if ($configExists) { Move-Item $configPath $backupPath -Force }
            $cfg = Get-ToolkitConfig
            $cfg.CompanyName | Should -Be "Dafna"
            $cfg.LogLevel | Should -Be "INFO"
            $cfg.MaxLogSizeMB | Should -Be 10
            $cfg.RetryCount | Should -Be 3
        }
        finally {
            if ($configExists -and (Test-Path $backupPath)) { Move-Item $backupPath $configPath -Force }
        }
    }

    It "Повинна завантажувати конфігурацію з файлу коли він існує" {
        $root = Get-ToolkitRoot
        $configPath = Join-Path $root "Config\ToolkitConfig.json"
        if (Test-Path $configPath) {
            $fileContent = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
            $cfg = Get-ToolkitConfig
            $cfg.CompanyName | Should -Be $fileContent.CompanyName
        } else {
            Set-ItResult -Skipped -Because "Конфіг-файл не знайдено"
        }
    }

    It "Повинна мати всі необхідні властивості конфігурації" {
        $cfg = Get-ToolkitConfig
        $expectedProps = @(
            "CompanyName", "DefaultBackupPath", "Subnet", "Description",
            "LogLevel", "MaxLogSizeMB", "BackupRetentionDays", "RemoteTimeoutSec",
            "RetryCount", "DiskSpaceWarningPercent", "DiskSpaceCriticalPercent",
            "CertExpiryWarnDays", "CriticalServices", "EmailSmtp", "EmailTo", "EmailFrom"
        )
        foreach ($prop in $expectedProps) {
            $cfg.PSObject.Properties.Name | Should -Contain $prop
        }
    }
}

# ============================================================
#  ConvertFrom-ParamString
# ============================================================

Describe "ConvertFrom-ParamString" {

    It "Повинна коректно розпарсити 'Key1=Value1;Key2=Value2'" {
        $result = ConvertFrom-ParamString -ParamString "Key1=Value1;Key2=Value2"
        $result | Should -BeOfType [hashtable]
        $result.Key1 | Should -Be "Value1"
        $result.Key2 | Should -Be "Value2"
    }

    It "Повинна повернути порожню хеш-таблицю для порожнього рядка" {
        $result = ConvertFrom-ParamString -ParamString ""
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Повинна повернути порожню хеш-таблицю для null" {
        $result = ConvertFrom-ParamString -ParamString $null
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Повинна обробити одну пару 'Key=Value'" {
        $result = ConvertFrom-ParamString -ParamString "Key=Value"
        $result.Key | Should -Be "Value"
        $result.Count | Should -Be 1
    }

    It "Повинна обробити значення зі знаком = всередині" {
        $result = ConvertFrom-ParamString -ParamString "Key=Val=ue"
        $result.Key | Should -Be "Val=ue"
    }

    It "Повинна ігнорувати записи без знаку =" {
        $result = ConvertFrom-ParamString -ParamString "Key1=Value1;NoEquals;Key2=Value2"
        $result.Count | Should -Be 2
    }

    It "Повинна обрізати пробіли з ключів та значень" {
        $result = ConvertFrom-ParamString -ParamString " Key1 = Value1 ; Key2 = Value2 "
        $result.Key1 | Should -Be "Value1"
        $result.Key2 | Should -Be "Value2"
    }
}

# ============================================================
#  Test-ComputerOnline
# ============================================================

Describe "Test-ComputerOnline" {

    It "Повинна повертати true для 'localhost'" {
        $result = Test-ComputerOnline -ComputerName "localhost"
        $result | Should -BeTrue
    }

    It "Повинна повертати false для недоступної адреси" {
        $result = Test-ComputerOnline -ComputerName "192.0.2.1" -TimeoutMs 1000
        $result | Should -BeFalse
    }

    It "Повинна приймати параметр -TimeoutMs" {
        { Test-ComputerOnline -ComputerName "localhost" -TimeoutMs 500 } | Should -Not -Throw
    }
}

# ============================================================
#  Write-TkLog
# ============================================================

Describe "Write-TkLog" {

    BeforeAll {
        $script:originalRoot = Get-ToolkitRoot
    }

    It "Повинна створити лог-файл" {
        Mock Get-ToolkitConfig { [pscustomobject]@{ LogLevel = "DEBUG"; MaxLogSizeMB = 10 } } -ModuleName ToolkitCommon
        & (Get-Module ToolkitCommon) { $script:ToolkitRoot = $args[0] } $TestDrive
        Write-TkLog -Message "Тестове повідомлення" -Level INFO
        $logFile = Join-Path $TestDrive "Logs\Toolkit.log"
        Test-Path $logFile | Should -BeTrue
    }

    It "Повинна записувати повідомлення з міткою часу" {
        Mock Get-ToolkitConfig { [pscustomobject]@{ LogLevel = "DEBUG"; MaxLogSizeMB = 10 } } -ModuleName ToolkitCommon
        & (Get-Module ToolkitCommon) { $script:ToolkitRoot = $args[0] } $TestDrive
        Write-TkLog -Message "Часовий тест" -Level INFO
        $content = Get-Content (Join-Path $TestDrive "Logs\Toolkit.log") -Encoding UTF8 | Select-Object -Last 1
        $content | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
    }

    It "Повинна включати рівень у запис логу" {
        Mock Get-ToolkitConfig { [pscustomobject]@{ LogLevel = "DEBUG"; MaxLogSizeMB = 10 } } -ModuleName ToolkitCommon
        & (Get-Module ToolkitCommon) { $script:ToolkitRoot = $args[0] } $TestDrive
        Write-TkLog -Message "Помилка тесту" -Level ERROR
        $content = Get-Content (Join-Path $TestDrive "Logs\Toolkit.log") -Encoding UTF8 | Select-Object -Last 1
        $content | Should -Match "\[ERROR\]"
    }

    It "Повинна ігнорувати DEBUG при рівні INFO" {
        $tempRoot = Join-Path $TestDrive "root2"
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Mock Get-ToolkitConfig { [pscustomobject]@{ LogLevel = "INFO"; MaxLogSizeMB = 10 } } -ModuleName ToolkitCommon
        & (Get-Module ToolkitCommon) { $script:ToolkitRoot = $args[0] } $tempRoot
        Write-TkLog -Message "Debug msg" -Level DEBUG
        $logFile = Join-Path $tempRoot "Logs\Toolkit.log"
        if (Test-Path $logFile) {
            Get-Content $logFile -Encoding UTF8 | Should -Not -Match "Debug msg"
        } else {
            $true | Should -BeTrue
        }
    }

    AfterAll {
        & (Get-Module ToolkitCommon) { $script:ToolkitRoot = $args[0] } $script:originalRoot
    }
}

# ============================================================
#  Invoke-WithRetry
# ============================================================

Describe "Invoke-WithRetry" {

    BeforeAll { Mock Write-TkLog {} -ModuleName ToolkitCommon }

    It "Повинна повертати результат при першому успіху" {
        $result = Invoke-WithRetry -ScriptBlock { "Успіх" } -MaxRetries 3 -DelaySeconds 0
        $result | Should -Be "Успіх"
    }

    It "Повинна повторювати спроби при помилці" {
        $script:callCount = 0
        $result = Invoke-WithRetry -ScriptBlock {
            $script:callCount++
            if ($script:callCount -lt 3) { throw "Помилка" }
            return "Успіх"
        } -MaxRetries 3 -DelaySeconds 0
        $result | Should -Be "Успіх"
        $script:callCount | Should -Be 3
    }

    It "Повинна кидати виключення після вичерпання спроб" {
        { Invoke-WithRetry -ScriptBlock { throw "Постійна помилка" } -MaxRetries 2 -DelaySeconds 0 } | Should -Throw
    }
}

# ============================================================
#  Export-TkReport
# ============================================================

Describe "Export-TkReport" {

    BeforeAll {
        Mock Write-TkLog {} -ModuleName ToolkitCommon
        $script:testData = @(
            [pscustomobject]@{ Name = "Server01"; Status = "Online" }
            [pscustomobject]@{ Name = "Server02"; Status = "Offline" }
        )
    }

    It "Повинна створювати CSV файл" {
        $path = Join-Path $TestDrive "report.csv"
        Export-TkReport -Data $script:testData -Path $path -Format CSV
        Test-Path $path | Should -BeTrue
        (Import-Csv $path).Count | Should -Be 2
    }

    It "Повинна створювати JSON файл" {
        $path = Join-Path $TestDrive "report.json"
        Export-TkReport -Data $script:testData -Path $path -Format JSON
        Test-Path $path | Should -BeTrue
    }

    It "Повинна створювати HTML файл з темною темою" {
        $path = Join-Path $TestDrive "report.html"
        Export-TkReport -Data $script:testData -Path $path -Format HTML -Title "Тест"
        $content = Get-Content $path -Raw -Encoding UTF8
        $content | Should -Match "background.*#1e1e2e"
        $content | Should -Match "<table"
    }

    It "Повинна створювати директорію якщо не існує" {
        $path = Join-Path $TestDrive "sub\folder\report.csv"
        Export-TkReport -Data $script:testData -Path $path -Format CSV
        Test-Path $path | Should -BeTrue
    }
}

# ============================================================
#  ConvertTo-TkResult
# ============================================================

Describe "ConvertTo-TkResult" {

    It "Повинна повертати об'єкт з Success" {
        $result = ConvertTo-TkResult
        $result.PSObject.Properties.Name | Should -Contain "Success"
    }

    It "Повинна мати Timestamp" {
        $result = ConvertTo-TkResult
        $result.Timestamp | Should -BeOfType [datetime]
    }

    It "Повинна мати Computer name" {
        $result = ConvertTo-TkResult
        $result.Computer | Should -Be $env:COMPUTERNAME
    }

    It "Success за замовчуванням true" {
        (ConvertTo-TkResult).Success | Should -BeTrue
    }

    It "Повинна зберігати Message" {
        (ConvertTo-TkResult -Message "test").Message | Should -Be "test"
    }

    It "Повинна зберігати Data" {
        $d = @{ Key = "Val" }
        (ConvertTo-TkResult -Data $d).Data.Key | Should -Be "Val"
    }
}

# ============================================================
#  Get-TkHostsList
# ============================================================

Describe "Get-TkHostsList" {

    It "Повинна повертати масив" {
        $hosts = Get-TkHostsList
        , $hosts | Should -BeOfType [System.Object[]]
    }

    It "Повинна повертати хости з властивістю Name" {
        $hosts = Get-TkHostsList
        if ($hosts.Count -gt 0) {
            $hosts[0].PSObject.Properties.Name | Should -Contain "Name"
        } else {
            Set-ItResult -Skipped -Because "Список хостів порожній"
        }
    }
}

# ============================================================
#  Assert-Administrator
# ============================================================

Describe "Assert-Administrator" {

    It "Не кидає виключення при наявності прав адміністратора" -Skip:(-not (
        [Security.Principal.WindowsPrincipal]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    )) {
        { Assert-Administrator } | Should -Not -Throw
    }
}
