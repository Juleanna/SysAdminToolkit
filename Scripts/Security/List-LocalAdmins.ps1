$group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
$members = @()
$group.psbase.Invoke("Members") | ForEach-Object {
    $obj = $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
    $members += $obj
}
$members | Sort-Object | ForEach-Object { Write-Host $_ }
