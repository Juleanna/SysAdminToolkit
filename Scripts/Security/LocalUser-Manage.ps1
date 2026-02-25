param(
    [Parameter(Mandatory=$true)][string]$Username,
    [ValidateSet('Create','Enable','Disable','ResetPassword','Status','Rename','Delete')]
    [string]$Mode = 'Status',
    [string]$Password,
    [string]$Description,
    [string]$NewName,
    [switch]$AddToAdministrators
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($Mode -ne 'Status' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Потрібні права адміністратора."
    exit 1
}

$hasLocalUser = Get-Command Get-LocalUser -ErrorAction SilentlyContinue

function To-Secure($pwd) {
    if ([string]::IsNullOrWhiteSpace($pwd)) { return $null }
    return ConvertTo-SecureString -String $pwd -AsPlainText -Force
}

if ($Mode -eq 'Status') {
    if ($hasLocalUser) {
        $u = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($null -eq $u) { Write-Error "Користувача не знайдено: $Username"; exit 1 }
        $admins = @{}
        try { Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | ForEach-Object { $admins[$_.Name]=$true } } catch {}
        [pscustomobject]@{
            Name=$u.Name; Enabled=$u.Enabled; LastLogon=$u.LastLogon; PasswordExpires=$u.PasswordExpires; IsAdmin=$admins.ContainsKey($u.Name)
        } | Format-List
    } else {
        try { net user $Username } catch { Write-Error "Не вдалося виконати net user: $($_.Exception.Message)"; exit 1 }
    }
    exit 0
}

switch ($Mode) {
    'Create' {
        if (-not $hasLocalUser) { Write-Error "Модуль LocalAccounts недоступний."; exit 1 }
        if (-not $Password) { Write-Error "Вкажіть пароль (-Password) для створення."; exit 1 }
        $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($existing) { Write-Error "Користувач вже існує."; exit 1 }
        $sec = To-Secure $Password
        try {
            New-LocalUser -Name $Username -Password $sec -Description $Description -ErrorAction Stop | Out-Null
            if ($AddToAdministrators) { Add-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction Stop }
            Write-Host "Користувача $Username створено." -ForegroundColor Green
        } catch {
            Write-Error "Не вдалося створити користувача: $($_.Exception.Message)"; exit 1
        }
    }
    'Enable' {
        if ($hasLocalUser) {
            try { Enable-LocalUser -Name $Username -ErrorAction Stop; Write-Host "Користувача $Username активовано." -ForegroundColor Green } catch { Write-Error "Не вдалося активувати: $($_.Exception.Message)"; exit 1 }
        } else {
            try { net user $Username /active:yes; Write-Host "Користувача $Username активовано (net user)." -ForegroundColor Green } catch { Write-Error "Не вдалося активувати: $($_.Exception.Message)"; exit 1 }
        }
    }
    'Disable' {
        if ($hasLocalUser) {
            try { Disable-LocalUser -Name $Username -ErrorAction Stop; Write-Host "Користувача $Username вимкнено." -ForegroundColor Yellow } catch { Write-Error "Не вдалося вимкнути: $($_.Exception.Message)"; exit 1 }
        } else {
            try { net user $Username /active:no; Write-Host "Користувача $Username вимкнено (net user)." -ForegroundColor Yellow } catch { Write-Error "Не вдалося вимкнути: $($_.Exception.Message)"; exit 1 }
        }
    }
    'ResetPassword' {
        if (-not $Password) { Write-Error "Вкажіть новий пароль (-Password)."; exit 1 }
        if ($hasLocalUser) {
            $sec = To-Secure $Password
            try { Set-LocalUser -Name $Username -Password $sec -ErrorAction Stop; Write-Host "Пароль користувача $Username змінено." -ForegroundColor Green; Write-TkLog "Пароль змінено: $Username" -Level INFO } catch { Write-Error "Не вдалося змінити пароль: $($_.Exception.Message)"; exit 1 }
        } else {
            try { net user $Username $Password; Write-Host "Пароль користувача $Username змінено (net user)." -ForegroundColor Green; Write-TkLog "Пароль змінено (net user): $Username" -Level INFO } catch { Write-Error "Не вдалося змінити пароль: $($_.Exception.Message)"; exit 1 }
        }
    }
    'Rename' {
        if (-not $NewName) { Write-Host "[ПОМИЛКА] Вкажіть нове ім'я (-NewName)." -ForegroundColor Red; exit 1 }
        if ($hasLocalUser) {
            $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
            if (-not $existing) { Write-Host "[ПОМИЛКА] Користувача '$Username' не знайдено." -ForegroundColor Red; exit 1 }
            $conflict = Get-LocalUser -Name $NewName -ErrorAction SilentlyContinue
            if ($conflict) { Write-Host "[ПОМИЛКА] Користувач '$NewName' вже існує." -ForegroundColor Red; exit 1 }
            try {
                Rename-LocalUser -Name $Username -NewName $NewName -ErrorAction Stop
                Write-Host "[OK] Користувача '$Username' перейменовано на '$NewName'." -ForegroundColor Green
                Write-TkLog "Перейменовано: '$Username' -> '$NewName'" -Level INFO
            } catch {
                Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Помилка перейменування '$Username': $($_.Exception.Message)" -Level ERROR
                exit 1
            }
        } else {
            try {
                $wmicResult = & wmic useraccount where "Name='$Username'" rename "$NewName" 2>&1
                if ($LASTEXITCODE -ne 0) { throw "wmic: $wmicResult" }
                Write-Host "[OK] Користувача '$Username' перейменовано на '$NewName' (wmic)." -ForegroundColor Green
                Write-TkLog "Перейменовано (wmic): '$Username' -> '$NewName'" -Level INFO
            } catch {
                Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Помилка перейменування (wmic) '$Username': $($_.Exception.Message)" -Level ERROR
                exit 1
            }
        }
    }
    'Delete' {
        if ($Username -eq $env:USERNAME) {
            Write-Host "[ПОМИЛКА] Неможливо видалити поточного користувача '$Username'." -ForegroundColor Red
            exit 1
        }
        if ($hasLocalUser) {
            $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
            if (-not $existing) { Write-Host "[ПОМИЛКА] Користувача '$Username' не знайдено." -ForegroundColor Red; exit 1 }
            try {
                Remove-LocalUser -Name $Username -ErrorAction Stop
                Write-Host "[OK] Користувача '$Username' видалено." -ForegroundColor Green
                Write-TkLog "Видалено користувача: '$Username'" -Level INFO
            } catch {
                Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Помилка видалення '$Username': $($_.Exception.Message)" -Level ERROR
                exit 1
            }
        } else {
            try {
                net user $Username /delete 2>&1
                if ($LASTEXITCODE -ne 0) { throw "net user /delete не вдалося" }
                Write-Host "[OK] Користувача '$Username' видалено (net user)." -ForegroundColor Green
                Write-TkLog "Видалено (net user): '$Username'" -Level INFO
            } catch {
                Write-Host "[ПОМИЛКА] $($_.Exception.Message)" -ForegroundColor Red
                Write-TkLog "Помилка видалення (net user) '$Username': $($_.Exception.Message)" -Level ERROR
                exit 1
            }
        }
    }
}
