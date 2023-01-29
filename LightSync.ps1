# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force
# winrm quickconfig / maybe??
# + Set Wifi network to Private

param(
  [switch]$Install,
  [string]$PackageFile,
  # TODO - To implement $Action filter
  [Parameter()][ValidateSet('exec', 'files', 'folders', 'fonts', 'paths', 'reg', 'shortcuts', 'symlink')][string]$Action,
  $ConfirmPreference = 'None'
)

. $PSScriptRoot/LightSyncHelper.ps1

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


