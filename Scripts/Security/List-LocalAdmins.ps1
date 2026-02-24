$hasLocalAccounts = Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue

if ($hasLocalAccounts) {
    try {
        $members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
        $members | Select-Object Name, ObjectClass, PrincipalSource | Sort-Object Name | Format-Table -AutoSize
    } catch {
        Write-Error "Не вдалося отримати список адміністраторів: $($_.Exception.Message)"
        exit 1
    }
} else {
    # Fallback для систем без модуля LocalAccounts
    try {
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
        $memberList = [System.Collections.ArrayList]::new()
        $group.psbase.Invoke("Members") | ForEach-Object {
            $name = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
            [void]$memberList.Add($name)
        }
        $memberList | Sort-Object | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Error "Не вдалося отримати список адміністраторів: $($_.Exception.Message)"
        exit 1
    }
}
