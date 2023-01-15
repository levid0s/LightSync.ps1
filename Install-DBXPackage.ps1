# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force
# winrm quickconfig / maybe??
# + Set Wifi network to Private

param(
  [Parameter(Mandatory = $true)][string]$PackageFile
)

Function Get-DropboxInstallPath() {
  $Path = "$env:LOCALAPPDATA\\Dropbox\\info.json"

  If(!(Test-Path $Path)) {
    Throw "$Path not found. Dropbox not installed?"
  }

  $data = Get-Content $path |ConvertFrom-Json
  return $data.personal.path
}

$InformationPreference = 'Continue'
$DebugPreference = 'Continue'
$VerbosePreference = 'Continue'

${Dry-Run} = $false

$DropboxRealRoot = Get-DropboxInstallPath

$DBXRoot = "N:\Tools"

$StartUp = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

$SubstFile = "$StartUp\subst-m-n.bat"
if (!(Test-Path $SubstFile)) {
  $formatText = @"
  subst m: $DropboxRealRoot\music
  subst n: $DropboxRealRoot
  timeout 2
"@
  Set-Content $SubstFile -Value $formatText
  $Subst
}

if (!((Test-Path 'M:') -and (Test-Path 'N:'))) {
  &$SubstFile
}

function Install-ModuleIfNotPresent {
  param(
    [string]$ModuleName
  )

  if (!(get-module $ModuleName -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-Module $ModuleName
  }
}

function TemplateStr {
  param(
    [string]$InputString
  )

  $NewString = $InputString -replace '{PkgName}', $PackageName
  $NewString = $NewString -replace '{PkgPath}', "$DBXRoot\$PackageName"
  $NewString = $NewString -replace '{DbxRoot}', "$DBXRoot"
  $NewString = $NewString -replace '/', '\'
  return $NewString
}


###
###  PATHs
###

function Get-EnvPathsArr {
  [OutputType([String[]])]  
  Param(
    [ValidateSet('User', 'Machine', 'All')]
    $Scope = 'All'
  )	
	
  $Paths = @()
	
  if ( @('Machine', 'All') -icontains $Scope) {
    $Paths += `
      [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine).Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
  }
	
  if ( @('User', 'All') -icontains $Scope) {
    $Paths += `
      [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User).Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
  }
	
  return $Paths
}

function Add-UserPaths {
  param(
    [string[]]$NewPaths
  )

  [String[]]$existingPathsUser = Get-EnvPathsArr('User')

  $NewPathsDiff = Compare-Object -ReferenceObject $existingPathsUser -DifferenceObject $NewPaths | `
    Where-Object SideIndicator -eq '=>' | `
    Select-Object -ExpandProperty InputObject

  if ($NewPathsDiff.Count -eq 0) {
    Write-Information "${actionVerb}: Paths already present, no changes needed."    
    return
  }

  $newEnvTargetUser = ($existingPathsUser + $NewPathsDiff) -join ';'

  Write-Verbose "${actionVerb}: Adding the following paths to user %PATH%:`n- $($NewPathsDiff -join "`n- ")`n"

  if (${Dry-Run} -eq $false) {
    [Environment]::SetEnvironmentVariable("Path", "$newEnvTargetUser", [System.EnvironmentVariableTarget]::User)
  }
  else {
    Write-Verbose "DRY-RUN: Setting User PATH to $newEnvTargetUser"
  }
}

function UnderscroreTo-HashTable() {
  param(
    [Parameter(Mandatory=$true)][System.Collections.Arraylist]$InputList,
    [System.Array]$Include=@(),
    [System.Array]$Exclude=@()
  )

  [System.Collections.Hashtable]$new=@{}

  Write-Debug "INputList= $InputList"
  Write-Debug "Keys= $($InputList.GetEnumerator())"

  foreach($k in $InputList.GetEnumerator()) {
    Write-Debug "Reading $($k.Name)"

    if( $PSBoundParameters.ContainsKey('Include') -and $k.Name -notin $Include) {
      Write-Debug "Key $($k.Name) not in Include list, skipping."
      continue
    }
    if($Exclude -icontains $k.Name) {
      Write-Debug "Key $($k.Name) is in Exclude list, skipping."
      continue
    }

    $new.Add("_$($k.Name)", $k.value)
    Write-Debug "Setting _$($k.Name) = $($k.value)"
  }

  return $new
}

###
###  Folders
###

function Get-ExeVersion() {
  param(
    [string]$Path
  )

  $version = (Get-Item $Path).VersionInfo.FileVersionRaw
  return $version
}

function Set-FolderComment() {
  param(
    [string]$Path,
    [string]$Comment
  )

  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path
  }

  $IniPath = "$Path\desktop.ini"
  if (!(Test-Path $IniPath)) {
    # Create the file from scratch if it doesn't exist

    $Content = @"
[.ShellClassInfo]
InfoTip=$Comment
"@
    Set-Content -Path $IniPath -Value $Content
  }

  else {
    # Update the File
    $Content = (Get-Content $IniPath ) -as [Collections.ArrayList]
    Write-Debug "Content of ${IniPath}:"
    Write-Debug [String[]]$Content

    $HeaderLineNumber = $Content | Select-String -Pattern  "^\[\.ShellClassInfo\]"  | Select-Object -First 1 -ExpandProperty LineNumber
    If (!$HeaderLineNumber) {
      $Content.Insert($Content.Count, "[.ShellClassInfo]")
      $HeaderLineNumber = $Content.Count
    }

    $CommentLineNumber = $Content | Select-String -Pattern "^InfoTip=" | Select-Object -First 1 -ExpandProperty LineNumber
    If (!$CommentLineNumber) {
      $Content.Insert($Content.Count, "InfoTip=$Comment")
    }
    else {
      $Content[$CommentLineNumber - 1] = "InfoTip=$Comment"
    }

    $Content | Set-Content -Path $IniPath -Force
  }

  # Check Attributes
  $IniFile = Get-ChildItem $IniPath -Force
  $IniAttr = $IniFile.Attributes

  if ($IniAttr -notlike '*Hidden*' -or $IniAttr -notlike '*System*') {
    $IniFile.Attributes = 'Hidden', 'System'
  }
}

###
###  Install Font
###

function Install-Font() {
  param(
    [string]$SourcePath
  )
  (New-Object -ComObject Shell.Application).Namespace(0x14).CopyHere($SourcePath, 0x14);
}

###
###  Create Shortcut
###

function New-Shortcut() {
  param(
    [Parameter(Mandatory = $true)][string]$LnkPath,
    [Parameter(Mandatory = $true)][string]$TargetExe,
    [string[]]$Arguments,
    [string]$WorkingDir,
    [string]$IconPath,
    [Parameter()][ValidateSet('Default', 'Minimized', 'Maximized')][string]$WindowStyle = 'Default'
  )

  $bitWindowStyle = @{
    Default   = 1;
    Maximized = 3;
    Minimized = 7
  }
 
  if($Arguments) {
    Write-Debug "[New-Shortcut]: Arguments supplied: $Arguments"
  }
  $WshShell = New-Object -comObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($LnkPath)
  $Shortcut.TargetPath = $TargetExe
  $Shortcut.Arguments = $Arguments -join " "
  $Shortcut.IconLocation = TemplateStr($IconPath)
  $Shortcut.WorkingDirectory = TemplateStr($WorkingDir)
  $Shortcut.WindowStyle = $bitWindowStyle[$WindowStyle]
  $Shortcut.Save()
}

function New-DBXShortcut() {
  param(
    [Parameter(Mandatory = $true)][string]$_Name,
    [Parameter()][ValidateSet('Programs-DBX', 'Startup')][string]$_Parent='Programs-DBX',
    [Parameter(Mandatory = $true)][string]$_Target,
    [Parameter()][ValidateSet('Default', 'Minimized', 'Maximized')][string]$_WindowStyle = 'Default',
    [string]$_Icon,
    [string[]]$_Args,
    [string]$_StartIn
  )

  if($_Args) {
    Write-Debug "Arguments supplied: $_Args"
  }

  $ParentPath = switch ($_Parent) {
    # Wshshell SpecialFolders
    "Programs-DBX" { [environment]::getfolderpath("Programs") + "\DBXSync" }
    "Startup" { [environment]::getfolderpath("Startup") }
  }

  $StartIn = switch ($_StartIn) {
    $null { Split-Path -Path TemplateStr($_Target) } # Start in the Target Exe's folder by default
    default { TemplateStr($s._StartIn) }
  }

  $Target = TemplateStr($_Target)

  $IconPath = TemplateStr($_Icon)
  if($IconPath -notmatch ",\d+$") { 
    $IconPath = "${IconPath},0"
  }

  New-Shortcut `
    -LnkPath "${ParentPath}\$(TemplateStr($_Name)) DBX.lnk" `
    -TargetExe $Target `
    -Arguments $_Args `
    -WorkingDir $StartIn `
    -IconPath $IconPath `
    -WindowStyle $_WindowStyle `
}


###
###  Program Start
###

Install-ModuleIfNotPresent 'PowerShell-YAML'

$PackageObj = Get-Content $PackageFile | ConvertFrom-Yaml
$PackageName = [System.IO.Path]::GetFileNameWithoutExtension($PackageFile)

###
###  Create Shortcuts
###

foreach ($s in $PackageObj.Shortcuts) {

  $ht = UnderscroreTo-HashTable -InputList $s -Include @('Name', 'Parent', 'Target', 'WindowStyle', 'Icon', 'Args', 'StartIn')

  New-DBXShortcut @ht

}

###
###  Install Font - TBC
###

foreach ($f in $PackageObj.Fonts) {
  Install-Font -SourcePath TemplateStr($f.path)
}

###
###  Set Folder Comments
###

foreach ($f in $PackageObj.Folders) {
  
  if ($f.VersionFrom) {
    $Version = Get-ExeVersion(TemplateStr($f.VersionFrom))
    Set-FolderComment -Path (TemplateStr($f.Path)) -Comment $Version
  }
}

###
###  ADD PATHs
###

if ($PackageObj.Paths) {
  $PathsStr = TemplateStr($PackageObj.Paths -join ';')
  $PathsList = $PathsStr -split ';'
  Add-UserPaths($PathsList)  
}

###
###  Create Registry Entries
###

Write-Debug "REG TIME"

foreach ($r in $PackageObj.reg) {
  write-Debug "Reg: $($r.key)"
  $r.key = $r.key -replace 'HKEY_CURRENT_USER\\', 'HKCU:\' -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:\'
  if (!$r.name) { $r.Name = '(Default)' }
  if (!$r.type) { $r.Type = 'String' }
	
  if (!(Test-Path $r.key)) {
    New-Item -Path $r.key -Force
  }
  New-ItemProperty -LiteralPath $r.key -Name $r.name -Value (TemplateStr($r.data)) -PropertyType $r.type -Verbose -Force
}


###
###  Do assocs manually
###

foreach ($s in $PackageObj.Shortcuts) {
  if ($s.Assoc) {
    $ExeName = Split-Path (TemplateStr($s.Target)) -Leaf
    $AppRegKey = "HKCU:\\SOFTWARE\\Classes\\Applications\\${ExeName}\\shell\\open\\command"
    if ($s.AssocParam -eq $null) { $s.AssocParam = "`"%1`"" }
    $OpenCmd = "$(TemplateStr($s.Target)) $($s.AssocParam)"
    if (!(Test-Path $AppRegKey)) {
      New-Item -Path $AppRegKey -Force
    }
    New-ItemProperty -LiteralPath $AppRegKey -Name "(Default)" -Value $OpenCmd -PropertyType "ExpandString" -Verbose -Force
  }

  if ($s.AssocIcon) {
    $AppRegKey = "HKCU:\\SOFTWARE\\Classes\\Applications\\${ExeName}\\DefaultIcon"
    $IconPath = TemplateStr($s.AssocIcon)

    if (!(Test-Path $AppRegKey)) {
      New-Item -Path $AppRegKey -Force
    }
    New-ItemProperty -LiteralPath $AppRegKey -Name "(Default)" -Value $IconPath -PropertyType "ExpandString" -Verbose -Force    
  }

  foreach ($ext in $s.Assoc) {
    $ExtRegKey = "HKCU:\\SOFTWARE\\Classes\\.${ext}\\OpenWithList\\${ExeName}"
    if (!(Test-Path $ExtRegKey)) {
      New-Item -Path $ExtRegKey -Force
    }
  }
}


###
###  Run the DSC
###

# $CredsNeeded = $PackageObj.Shortcuts.Assoc -ne $null

# if ($CredsNeeded -and $PsDscRunAsCreds -eq $null) {
#   Throw 'Please run:    [PSCredential]$PsDscRunAsCreds = Get-Credential   '
# }

# Remove-DscConfigurationDocument -Stage Pending
# Invoke-Expression "$PackageNameDSC -ConfigurationData `$Config -OutputPath `"./mofs/$PackageNameDSC`" "
# Start-DscConfiguration -Wait -Verbose -Path "./mofs/$PackageNameDSC"
