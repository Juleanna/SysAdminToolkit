$scripts = @(
  'Inventory\Get-PC-Inventory.ps1',
  'Inventory\Get-InstalledSoftware.ps1',
  'Telegram\Send-LastInventoryToTG.ps1',
  'Monitoring\Check-Performance.ps1',
  'Monitoring\Export-EventLogs.ps1',
  'Monitoring\Check-ServiceUptime.ps1',
  'Monitoring\Check-DiskSpace.ps1',
  'Monitoring\Watch-EventLog.ps1',
  'Monitoring\Check-PendingReboot.ps1',
  'Services\Service-Monitor.ps1',
  'Services\Service-Restart.ps1',
  'Services\Service-AutoRecover.ps1',
  'Disks\Disk-Health.ps1',
  'Disks\Disk-SpaceReport.ps1',
  'Disks\Cleanup-OldFiles.ps1',
  'Disks\Disk-QuotaReport.ps1',
  'Disks\Optimize-Disk.ps1',
  'Certificates\Cert-ExpiryCheck.ps1',
  'Certificates\Cert-Install.ps1',
  'ScheduledTasks\ScheduledTask-Report.ps1',
  'ScheduledTasks\ScheduledTask-Create.ps1',
  'Backup\Backup-Folder.ps1',
  'Backup\Backup-UserProfiles.ps1',
  'Backup\Backup-ScheduledTask.ps1',
  'Backup\Backup-GPO.ps1',
  'Backup\Backup-Registry.ps1',
  'Backup\Backup-Drivers.ps1',
  'Backup\Clean-OldBackups.ps1',
  'Network\Test-Network.ps1',
  'Network\Scan-LAN.ps1',
  'Recovery\Repair-Network.ps1',
  'Network\Test-Ports.ps1',
  'Network\Get-DNSRecords.ps1',
  'Network\Trace-Route.ps1',
  'Network\Test-Bandwidth.ps1',
  'Printers\Add-NetworkPrinter.ps1',
  'Printers\Remove-Printer.ps1',
  'Printers\Restart-Spooler.ps1',
  'Profiles\Delete-OldProfiles.ps1',
  'Profiles\Clean-UserProfile.ps1',
  'Mass\Restart-Computers.ps1',
  'Mass\Run-OnMultiple.ps1',
  'ActiveDirectory\AD-UserReport.ps1',
  'ActiveDirectory\AD-ComputerReport.ps1',
  'ActiveDirectory\AD-GroupMembership.ps1',
  'Security\Toggle-USBStorage.ps1',
  'Security\List-LocalAdmins.ps1',
  'Security\Quick-Malware-Check.ps1',
  'Security\Firewall-Profile.ps1',
  'Security\Toggle-RDP.ps1',
  'Security\PasswordPolicy-Report.ps1',
  'Security\Defender-QuickScan.ps1',
  'Security\BitLocker-Status.ps1',
  'Security\LocalUsers-Report.ps1',
  'Security\LocalUser-Manage.ps1',
  'Security\Audit-Report.ps1',
  'Security\RemoteAccess-Hardening.ps1',
  'Security\AuditPolicy-Apply.ps1',
  'Security\AccountProtection.ps1',
  'Security\Autoruns-Report.ps1',
  'Security\SecurityUpdates.ps1',
  'Security\Audit-SharedFolders.ps1',
  'Security\Check-OpenPorts.ps1',
  'Security\Export-SecurityBaseline.ps1',
  'Security\Audit-Permissions.ps1',
  'Security\Check-WeakPasswords.ps1',
  'Security\Sign-Scripts.ps1',
  'Recovery\Repair-Windows.ps1',
  'Recovery\Restore-UserProfile.ps1',
  'Recovery\Repair-DiskErrors.ps1',
  'Recovery\Reset-WindowsUpdate.ps1',
  'Recovery\Manage-RestorePoints.ps1',
  'Utils\Clean-Temp.ps1',
  'Utils\Collect-Logs.ps1',
  'Utils\System-Info.ps1',
  'Utils\Compare-Configs.ps1',
  'Utils\New-ISOImage.ps1',
  'Utils\Clean-SystemJunk.ps1',
  'Reports\Daily-Report.ps1',
  'Reports\Compare-Snapshot.ps1',
  'Telegram\Test-TGMessage.ps1',
  'Telegram\Send-TGAlert.ps1',
  'RemoteHelp\Get-RemoteProcesses.ps1',
  'RemoteHelp\Kill-RemoteProcess.ps1',
  'RemoteHelp\Popup-Message.ps1',
  'RemoteHelp\Collect-RemoteLogs.ps1',
  'RemoteHelp\Run-RemoteCommand.ps1'
)
$missing = @()
foreach ($s in $scripts) {
  $full = Join-Path $PSScriptRoot "Scripts\$s"
  if (-not (Test-Path $full)) { $missing += $s }
}
if ($missing.Count -eq 0) { Write-Host "ALL OK: all $($scripts.Count) script paths exist" -ForegroundColor Green }
else { Write-Host "MISSING $($missing.Count):" -ForegroundColor Red; $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }
Write-Host "Total checked: $($scripts.Count)"

# Also check ToolkitCommon exports
Write-Host ""
Write-Host "--- Module check ---"
$modPath = Join-Path $PSScriptRoot "Scripts\Utils\ToolkitCommon.psm1"
$modContent = Get-Content $modPath -Raw
$expectedFunctions = @(
  'Get-ToolkitRoot','Get-ToolkitConfig','Get-TkHostsList','ConvertFrom-ParamString',
  'Assert-Administrator','Test-ComputerOnline','Write-TkLog','Invoke-WithRetry',
  'Export-TkReport','ConvertTo-TkResult','Send-TkEmail',
  'Show-TkNotification','Invoke-TkRemote','Get-TkCredential','Test-TkPrerequisite',
  'ConvertTo-TkHtmlDashboard','Write-TkEventLog','Get-TkUserRole','Test-TkRoleAccess'
)
$missingFn = @()
foreach ($fn in $expectedFunctions) {
  if ($modContent -notmatch "function\s+$fn") { $missingFn += $fn }
}
if ($missingFn.Count -eq 0) { Write-Host "ALL OK: all $($expectedFunctions.Count) functions found in module" -ForegroundColor Green }
else { Write-Host "MISSING functions:" -ForegroundColor Red; $missingFn | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }

# Check docs
Write-Host ""
Write-Host "--- Docs check ---"
$docs = @('README.md','CLAUDE.md','CHANGELOG.md','Install.ps1','Update-Toolkit.ps1','.PSScriptAnalyzerSettings.psd1','Config\Roles.json','Tests\ToolkitCommon.Tests.ps1')
$missingDocs = @()
foreach ($d in $docs) {
  if (-not (Test-Path (Join-Path $PSScriptRoot $d))) { $missingDocs += $d }
}
if ($missingDocs.Count -eq 0) { Write-Host "ALL OK: all $($docs.Count) doc/config files exist" -ForegroundColor Green }
else { Write-Host "MISSING:" -ForegroundColor Red; $missingDocs | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }

# Check BOM on key files
Write-Host ""
Write-Host "--- BOM check (sample) ---"
$bomFiles = @('SysAdminToolkit.GUI.ps1','Scripts\Utils\ToolkitCommon.psm1','Scripts\Recovery\Repair-DiskErrors.ps1','Scripts\Backup\Backup-Registry.ps1','Scripts\Utils\Clean-SystemJunk.ps1','Scripts\Disks\Optimize-Disk.ps1')
foreach ($bf in $bomFiles) {
  $fp = Join-Path $PSScriptRoot $bf
  if (Test-Path $fp) {
    $bytes = [System.IO.File]::ReadAllBytes($fp)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $icon = if ($hasBom) { "OK" } else { "NO BOM" }
    $color = if ($hasBom) { "Green" } else { "Red" }
    Write-Host "  $icon $bf" -ForegroundColor $color
  }
}
