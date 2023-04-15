<#
.SYNOPSIS
Scirpt to recursively configure Dropbox to ignore .terraform folders.
https://help.dropbox.com/sync/ignored-files
.Parameter Path
The path to the Dropbox folder. If not specified, the current directory is used.
#>

param(
  ## Mandatory parameter
  [Parameter(Mandatory = $true)][ValidateSet('Search', 'ExactPath')][string]$Type,
  [string]$Path = $PWD.Path,
  [string]$Filter = '.terraform',

  [switch]$Unignore
)


Function Get-DropboxInstallPath() {
  <#
  .SYNOPSIS
  Get the Dropbox data folder of the current user
  #>
  $Path = "$env:LOCALAPPDATA\\Dropbox\\info.json"

  if (!(Test-Path $Path)) {
    Throw "$Path not found. Dropbox not installed?"
  }

  $Data = Get-Content $Path | ConvertFrom-Json
  Return $Data.personal.path
}

Function Get-SubstedPaths {
  <#
  Get a Hashtable of Substed paths
  #>

  $SubstOut = $(subst)
  $SubstedPaths = @{}
  $SubstOut | ForEach-Object { 
    $SubstedPaths[($_ -Split '\: => ')[0]] = ($_ -Split '\: => ')[1]
  }
  return $SubstedPaths
}

Function Get-RealPath {
  <#
  Checks if the path is substed and returns the real path.
  Otherwise returns the current path.
  #>

  param(
    [string]$Path
  )

  $SubstedPaths = Get-SubstedPaths
  if ($SubstedPaths.Keys -contains $PWD.Drive.Root) {
    return $SubstedPaths[$PWD.Drive.Root] + $Path.Substring(2)
  }
  else {
    return $Path
  }
}

Function Validate-Path {
  <#
  Validates if the path is within dropbox
  #>
  param(
    [string]$Path
  )
  
  $DropboxRoot = Get-DropboxInstallPath
  if ($Path.StartsWith($DropboxRoot)) {
    return $true
  }
  else {
    return $false
  }
}

$Path = Get-RealPath $Path
if (!(Validate-Path $Path)) {
  Throw "Path ``$Path`` is not within Dropbox"
}

if ($Type -eq 'Search') {
  $Folders = (Get-ChildItem $Path -Recurse -Directory -Filter $Filter -Force).FullName
}
else {
  $Folders = $Path
}

if ($Unignore) {
  $Action = 'Unignoring'
  $IgnoreValue = 0
}
else {
  $Action = 'Ignoring'
  $IgnoreValue = 1
}

$StreamName = 'com.dropbox.ignored'

if ($DebugPreference -eq 'Continue' -and $Folders.Count -gt 1) {
  Write-Debug "Found $($folders.Count) folders to process:`n$($folders -join "`n")`n"
  Pause
}

foreach ($f in $Folders) {
  Write-Debug "Processing: ``$f``"
  If ((Get-Content -Path $f -Stream $StreamName -ErrorAction SilentlyContinue) -in @(0, $null)) {
    Write-Output "${Action}: ``$f``"
    Set-Content -Path $f -Stream com.dropbox.ignored -Value 1
  }
  else {
    Write-Debug "Already ignored: ``$f``"
  }
}
