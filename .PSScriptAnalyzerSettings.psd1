@{
    # Правила, які виключаються з аналізу
    ExcludeRules = @(
        # Write-Host використовується навмисно для кольорового виводу у GUI та консольних скриптах
        'PSAvoidUsingWriteHost',

        # Багато скриптів змінюють стан системи без ShouldProcess (by design для адмін-тулкіту)
        'PSUseShouldProcessForStateChangingFunctions'
    )

    # Мінімальний рівень серйозності для звітування
    Severity = @(
        'Warning',
        'Error'
    )

    Rules = @{
        # Перевірка сумісності з конкретними версіями PowerShell
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
