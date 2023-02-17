# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force
# winrm quickconfig / maybe??
# + Set Wifi network to Private

param(
  [switch]$Install,
  [string]$PackageFile,
  # TODO - To implement $Action filter
  [Parameter()][ValidateSet('exec', 'files', 'folders', 'fonts', 'paths', 'reg', 'shortcuts', 'symlink')][string]$Action,
  $ConfirmPreference = 'None',
  $DebugPreference = 'Continue'
)

$DebugPreference = 'Continue'

. $PSScriptRoot/_LightSyncHelper.ps1

Write-DebugLog "Starting script"

if ($Install) {
  Install-Dependencies
  Invoke-PackagesWizard
  Install-LightSyncDrive # Subst in Startup

  Write-Debug "Adding $PSScriptRoot to User PATH"
  Add-UserPaths -Paths $PSScriptRoot

  $MyScript = $MyInvocation.MyCommand.Source
  Register-LightSyncScheduledTask -ScriptPath $MyScript
  return
}

Invoke-LightSync -PackageFile $PackageFile

Update-PathsInShell

Write-DebugLog "Exiting"
