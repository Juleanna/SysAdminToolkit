<#
.SYNOPSIS
    Відображає членів групи Active Directory з ієрархічним виводом.
.DESCRIPTION
    Отримує список членів вказаної AD-групи через Get-ADGroupMember.
    За наявності прапорця -Recursive рекурсивно розгортає вкладені групи
    та відображає ієрархічну структуру з відступами. Без прапорця показує
    лише прямих членів групи.
.PARAMETER GroupName
    Назва групи Active Directory для аналізу.
    За замовчуванням: "Domain Admins".
.PARAMETER Recursive
    Якщо вказано, рекурсивно розгортає вкладені групи та показує ієрархію.
.EXAMPLE
    .\AD-GroupMembership.ps1
    Показує прямих членів групи "Domain Admins".
.EXAMPLE
    .\AD-GroupMembership.ps1 -GroupName "IT-Department" -Recursive
    Рекурсивно показує всіх членів групи "IT-Department" з ієрархією.
#>
param(
    [string]$GroupName = "Domain Admins",
    [switch]$Recursive
)

Import-Module "$PSScriptRoot\..\Utils\ToolkitCommon.psm1" -Force

Write-TkLog "Запуск AD-GroupMembership (Group=$GroupName, Recursive=$Recursive)" -Level INFO

# --- Перевірка модуля ActiveDirectory ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Модуль ActiveDirectory не знайдено. Встановіть RSAT." -ForegroundColor Red
    Write-TkLog "Модуль ActiveDirectory не знайдено" -Level ERROR
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

# --- Рекурсивна функція для відображення ієрархії ---
function Show-GroupHierarchy {
    param(
        [string]$Group,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$Visited
    )

    $indent = "  " * $Depth
    $prefix = if ($Depth -gt 0) { "${indent}+-- " } else { "" }

    try {
        $members = Get-ADGroupMember -Identity $Group -ErrorAction Stop
    } catch {
        Write-Host "${indent}    [Помилка: $($_.Exception.Message)]" -ForegroundColor Red
        return
    }

    foreach ($member in $members) {
        switch ($member.objectClass) {
            'group' {
                Write-Host "${prefix}[Група] $($member.Name)" -ForegroundColor Magenta
                if ($Visited.Contains($member.SamAccountName)) {
                    Write-Host "${indent}    (вже відображено, пропускаємо циклічне посилання)" -ForegroundColor DarkGray
                } else {
                    $Visited.Add($member.SamAccountName) | Out-Null
                    Show-GroupHierarchy -Group $member.SamAccountName -Depth ($Depth + 1) -Visited $Visited
                }
            }
            'user' {
                try {
                    $userDetails = Get-ADUser -Identity $member.SamAccountName -Properties DisplayName, Title, Department, Enabled
                    $status = if ($userDetails.Enabled) { "Активний" } else { "Вимкнений" }
                    $statusColor = if ($userDetails.Enabled) { "Green" } else { "Red" }
                    Write-Host "${prefix}[Користувач] " -NoNewline -ForegroundColor White
                    Write-Host "$($member.Name)" -NoNewline -ForegroundColor Cyan
                    Write-Host " ($($userDetails.SamAccountName))" -NoNewline -ForegroundColor DarkCyan
                    if ($userDetails.Title) { Write-Host " - $($userDetails.Title)" -NoNewline -ForegroundColor Gray }
                    if ($userDetails.Department) { Write-Host " [$($userDetails.Department)]" -NoNewline -ForegroundColor Gray }
                    Write-Host " [$status]" -ForegroundColor $statusColor
                } catch {
                    Write-Host "${prefix}[Користувач] $($member.Name) ($($member.SamAccountName))" -ForegroundColor Cyan
                }
            }
            'computer' {
                Write-Host "${prefix}[Комп'ютер] $($member.Name)" -ForegroundColor Yellow
            }
            default {
                Write-Host "${prefix}[$($member.objectClass)] $($member.Name)" -ForegroundColor Gray
            }
        }
    }
}

try {
    # --- Перевірка існування групи ---
    try {
        $groupObj = Get-ADGroup -Identity $GroupName -Properties Description, ManagedBy, WhenCreated -ErrorAction Stop
    } catch {
        Write-Host "Групу '$GroupName' не знайдено в Active Directory." -ForegroundColor Red
        Write-TkLog "Групу '$GroupName' не знайдено" -Level ERROR
        exit 1
    }

    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "         ЧЛЕНСТВО В ГРУПI AD" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "Група:       $($groupObj.Name)" -ForegroundColor Cyan
    Write-Host "Опис:        $(if ($groupObj.Description) { $groupObj.Description } else { '-' })" -ForegroundColor Cyan
    Write-Host "Категорія:   $($groupObj.GroupCategory)" -ForegroundColor Cyan
    Write-Host "Область:     $($groupObj.GroupScope)" -ForegroundColor Cyan
    Write-Host "Створено:    $($groupObj.WhenCreated.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
    if ($groupObj.ManagedBy) {
        try {
            $manager = Get-ADUser -Identity $groupObj.ManagedBy -Properties DisplayName
            Write-Host "Керуючий:    $($manager.DisplayName)" -ForegroundColor Cyan
        } catch {
            Write-Host "Керуючий:    $($groupObj.ManagedBy)" -ForegroundColor Cyan
        }
    }
    Write-Host "Режим:       $(if ($Recursive) { 'Рекурсивний' } else { 'Прямі члени' })" -ForegroundColor Cyan
    Write-Host "=====================================================`n" -ForegroundColor Cyan

    if ($Recursive) {
        # --- Рекурсивний режим з ієрархією ---
        Write-Host "[Група] $($groupObj.Name)" -ForegroundColor Magenta
        $visited = New-Object 'System.Collections.Generic.HashSet[string]'
        $visited.Add($GroupName) | Out-Null
        Show-GroupHierarchy -Group $GroupName -Depth 1 -Visited $visited

        # --- Підсумок: загальна кількість унікальних членів ---
        Write-Host ""
        try {
            $allMembers = Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction Stop
            $userCount    = @($allMembers | Where-Object { $_.objectClass -eq 'user' }).Count
            $computerCount = @($allMembers | Where-Object { $_.objectClass -eq 'computer' }).Count
            Write-Host "--- Підсумок (рекурсивно) ---" -ForegroundColor Cyan
            Write-Host "Унікальних користувачів: " -NoNewline; Write-Host "$userCount" -ForegroundColor Green
            Write-Host "Комп'ютерів:             " -NoNewline; Write-Host "$computerCount" -ForegroundColor Yellow
        } catch {
            Write-TkLog "Помилка підрахунку рекурсивних членів: $($_.Exception.Message)" -Level WARN
        }
    } else {
        # --- Прямі члени ---
        try {
            $directMembers = Get-ADGroupMember -Identity $GroupName -ErrorAction Stop
        } catch {
            Write-Host "Не вдалося отримати членів групи: $($_.Exception.Message)" -ForegroundColor Red
            Write-TkLog "Помилка Get-ADGroupMember: $($_.Exception.Message)" -Level ERROR
            exit 1
        }

        if (-not $directMembers -or @($directMembers).Count -eq 0) {
            Write-Host "Група '$GroupName' порожня." -ForegroundColor Yellow
        } else {
            $tableData = @()
            foreach ($member in $directMembers) {
                $type = switch ($member.objectClass) {
                    'user'     { 'Користувач' }
                    'group'    { 'Група' }
                    'computer' { "Комп'ютер" }
                    default    { $member.objectClass }
                }

                $displayName = '-'
                $enabled = '-'
                if ($member.objectClass -eq 'user') {
                    try {
                        $u = Get-ADUser -Identity $member.SamAccountName -Properties DisplayName, Enabled
                        $displayName = $u.DisplayName
                        $enabled = if ($u.Enabled) { 'Так' } else { 'Ні' }
                    } catch { }
                }

                $tableData += [pscustomobject]@{
                    Тип        = $type
                    Ім_я       = $member.Name
                    Логін      = $member.SamAccountName
                    Повне_ім_я = $displayName
                    Активний   = $enabled
                }
            }

            $tableData | Format-Table -AutoSize

            $groups   = @($directMembers | Where-Object { $_.objectClass -eq 'group' }).Count
            $users    = @($directMembers | Where-Object { $_.objectClass -eq 'user' }).Count
            $computers = @($directMembers | Where-Object { $_.objectClass -eq 'computer' }).Count

            Write-Host "--- Підсумок ---" -ForegroundColor Cyan
            Write-Host "Всього прямих членів: $(@($directMembers).Count)" -ForegroundColor Cyan
            if ($users -gt 0)     { Write-Host "  Користувачів: $users" -ForegroundColor Green }
            if ($groups -gt 0)    { Write-Host "  Вкладених груп: $groups" -ForegroundColor Magenta }
            if ($computers -gt 0) { Write-Host "  Комп'ютерів: $computers" -ForegroundColor Yellow }
        }
    }

    Write-TkLog "AD-GroupMembership завершено для '$GroupName'" -Level INFO

} catch {
    $errMsg = "Критична помилка AD-GroupMembership: $($_.Exception.Message)"
    Write-TkLog $errMsg -Level ERROR
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
