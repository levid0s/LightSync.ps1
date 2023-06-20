# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force
# winrm quickconfig / maybe??
# + Set Wifi network to Private

param(
  [Parameter(Position = 0)][string]$PackageFile,
  [Parameter()][ValidateSet('exec', 'files', 'folders', 'fonts', 'paths', 'reg', 'shortcuts', 'symlink', 'junction', 'regswild', 'dropboxignore', 'dropboxoffline' )][string]$Action,
  [switch]$InvokeToAdmin,
  [switch]$Install,
  $ConfirmPreference = 'None',
  $DebugPreference = 'Continue',
  [bool]$testBool
)
$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'
# $VerbosePreference = 'Continue'

$ScriptRoot = $PSScriptRoot
if (!$ScriptRoot) {
  $ScriptRoot = Get-Location
}

. "$ScriptRoot/../../src/useful/ps-winhelpers/_PS-WinHelpers.ps1"
. "$ScriptRoot/experiments/Experiments.ps1"
. "$ScriptRoot/_LightSyncHelper.ps1"

Write-DebugLog 'Starting LightSync'

if ($InvokeToAdmin -and -not (IsAdmin)) {
  Write-Debug 'Elevating to Admin'

  $CustomArguments = @{InvokeToAdmin = $true }

  if ($PackageFile) { $CustomArguments.PackageFile = Resolve-Path $PackageFile }
  Invoke-ToAdmin -CustomArguments $CustomArguments
  Return
}

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

if ($PackageFile -in @('...', '?')) {
  $PackageFile = Invoke-FilePicker -Filter 'LightSync Package (*.yaml)|*.yaml' -Path "$ScriptRoot/packages"
}

$LogPath = "$env:LOCALAPPDATA\Temp\LightSync\LightSync-$(Get-Date -Format 'yyyy-MM-dd').log"
if (!(Test-Path (Split-Path $LogPath) -PathType Container)) {
  New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogPath -Append
Invoke-LightSync -PackageFile $PackageFile
Stop-Transcript

Update-PathsInShell

if ($InvokeToAdmin -and (IsAdmin)) {
  Read-Host 'Press enter to exit' | Out-Null
}

Write-DebugLog 'Exiting LightSync.'
