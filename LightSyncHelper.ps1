$STARTUP = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$LSDREG = "HKEY_CURRENT_USER\SOFTWARE\LightSync"
Set-Variable -Name LIGHTSYNCROOT -Value (Get-LighSyncDrivePath).DrivePath -Option Constant -Scope Global -Force

###
###  Low Level Functions
###    ie do stuff with the OS
###

##
##  Registry Functions
##

function Get-RegValue {
  <#
  .SYNOPSIS
  Read a value from the registry
  .DESCRIPTION
  This is a simplified version of the Get-ItemPropertyValue function.
  No need to specify the Value Name and Path in separate parameters.
  Supports multiple namings for the HKCU and HKLM root keys for convenience.
  .PARAMETER FullPath
  The full path to the registry value, including the value name.
  .PARAMETER ErrorAction
  The error action to use when the registry value does not exist. Set it to SilentyContinue to return $null instead of throwing an error.
  .EXAMPLE
  Get-RegValue -FullPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders\Personal'
  .EXAMPLE
  Get-RegValue -FullPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders\Personal' -ErrorAction SilentlyContinue
  #>

  param(
    [string]$FullPath,
    # Add ErrorAction parameter:
    [ValidateSet('SilentlyContinue', 'Stop', 'Ignore', 'Inquire', 'Continue')][string]$ErrorAction = 'Stop'
  )

  $Path = Split-Path $FullPath -Parent
  $Path = $Path -replace '^(HKCU|HKEY_CURRENT_USER|HKEY_CURRENT_USER:)\\', 'HKCU:\'
  $Path = $Path -replace '^(HKLM|HKEY_LOCAL_MACHINE|HKEY_LOCAL_MACHINE:)\\', 'HKLM:\'

  $Name = Split-Path $FullPath -Leaf

  # Get-ItemPropertyValue has a bug: https://github.com/PowerShell/PowerShell/issues/5906
  $Value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction $ErrorAction | select -ExpandProperty $Name

  Return $Value
}

function Set-RegValue {
  <#
  .SYNOPSIS
  Write a value to the registry
  .DESCRIPTION
  This is a simplified version of the New-ItemProperty function.
  No need to specify the Value name and Path in separate parameters.
  Accepts various spellings of the HKCU and HKLM root keys for convenience.
  .PARAMETER FullPath
  The full path to the registry value, including the value name.
  For default values, use (Default)
  .PARAMETER Value
  The value to write to the registry. This parameter is of string[] type but type conversion is performed automatically for other value type (DWORD, etc.).
  .PARAMETER Type
  The Value's data type to be written. Supports both the .Net (String) and the registry (REG_SZ) names for convenience.
  .PARAMETER Force
  Create the registry key (including the full path) if it does not exist.
  .EXAMPLE
  Set-RegValue -FullPath 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions' -Value 1 -Type DWord
  .EXAMPLE
  Set-RegValue -FullPath 'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\MultiTaskingAltTabFilter' -Value 3 -Type REG_DWORD -Force
  #>

  param(
    [string]$FullPath,
    [string[]]$Value,
    [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord', 'REG_SZ', 'REG_EXPAND_SZ', 'REG_BINARY', 'REG_DWORD', 'REG_MULTI_SZ', 'REG_QWORD')][string]$Type,
    [switch]$Force
  )
  
  # Accept REG_* types for ease of use
  $LookupTable = @{
    'REG_SZ'        = 'String'
    'REG_EXPAND_SZ' = 'ExpandString'
    'REG_BINARY'    = 'Binary'
    'REG_DWORD'     = 'DWord'
    'REG_MULTI_SZ'  = 'MultiString'
    'REG_QWORD'     = 'QWord'
  }

  if ($LookupTable.ContainsKey($Type)) {
    $Type = $LookupTable[$Type]
  }

  $Path = Split-Path $FullPath -Parent
  $Path = $Path -replace '^(HKCU|HKEY_CURRENT_USER|HKEY_CURRENT_USER:)\\', 'HKCU:\'
  $Path = $Path -replace '^(HKLM|HKEY_LOCAL_MACHINE|HKEY_LOCAL_MACHINE:)\\', 'HKLM:\'

  $Name = Split-Path $FullPath -Leaf

  if ($Force) {
    if (!(Test-Path $Path)) {
      New-Item -Path $Path -Force      
    }
  }

  switch -wildcard ($Type) {
    "*String" { $ValueConv = $Value }
    'Binary' { Throw "Set-RegValue -Type Binary : Not implemented" }
    'DWord' { $ValueConv = [System.Convert]::ToUInt32($Value[0]) }
    'QWord' { $ValueConv = [System.Convert]::ToUInt64($Value[0]) }
  }
  New-ItemProperty -Path $Path -Name $Name -Value $ValueConv -PropertyType $Type -Force | Out-Null
  Write-Debug "[Set-RegValue]: Writing to registry: $Path\$Name = $ValueConv ($Type)"
}

##
##  Shortcuts
##

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

  $ParentPath = Split-Path $LnkPath -Parent
  if (!(Test-Path $ParentPath)) {
    New-Item -Path $ParentPath -ItemType Directory -Force
  }
 
  if ($Arguments) {
    Write-Debug "[New-Shortcut]: Arguments supplied: $Arguments"
  }
  $WshShell = New-Object -comObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($LnkPath)
  $Shortcut.TargetPath = $TargetExe
  $Shortcut.Arguments = $Arguments -join " "
  $Shortcut.IconLocation = $IconPath
  $Shortcut.WorkingDirectory = $WorkingDir
  $Shortcut.WindowStyle = $bitWindowStyle[$WindowStyle]
  $Shortcut.Save()
}


###
###  ASSOC
###

function New-FileAssoc {
  param(
    [Parameter(Mandatory = $true)][string]$Extension,
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $false)][string]$Params,
    [Parameter(Mandatory = $false)][string]$IconPath
  )

  $Extension = $Extension -replace '^\.', '' # Remove traling dot if supplied by accident

  $ExeName = Split-Path $ExePath -Leaf
  if ([string]::IsNullOrEmpty($Params)) { $Params = "`"%1`"" }
  $OpenCmd = "$ExePath $Params"

  $AppRegKey = "HKCU:\SOFTWARE\Classes\Applications\${ExeName}\shell\open\command\(Default)"
  Set-RegValue -FullPath $AppRegKey -Value $OpenCmd -Type REG_EXPAND_SZ -Force

  $OpenWithRegKey = "HKCU:\SOFTWARE\Classes\.${Extension}\OpenWithList\${ExeName}\(Default)"
  Set-RegValue -FullPath $OpenWithRegKey -Value $null -Type REG_SZ -Force

  if ($IconPath) {
    $IconRegKey = "HKCU:\SOFTWARE\Classes\Applications\${ExeName}\DefaultIcon\(Default)"
    Set-RegValue -FullPath $IconRegKey -Value $IconPath -Type REG_EXPAND_SZ -Force
  }
}

##
##  PATHs
##

function Get-EnvPathsArr {
  <#
  .SYNOPSIS
  Get the PATH environment variable as an array. Can get either the User or Machine scope, or both.
  .PARAMETER Scope
  The scope of the PATH variable to get. Can be 'User', 'Machine' or 'All'.
  .EXAMPLE
  Get-EnvPathsArr -Scope User
  .EXAMPLE  
  #>
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
  <#
  .SYNOPSIS
  Add additional paths to the USER scope PATH environment variable.
  .DESCRIPTION
  This function adds paths to the user's PATH environment variable. It does not remove any existing paths.
  .PARAMETER NewPaths
  The paths to add to the user PATH environment variable.
  .EXAMPLE
  Add-UserPaths -NewPaths 'C:\Program Files\Git\cmd', 'C:\Program Files\Git\usr\bin'
  #>

  param(
    [string[]]$NewPaths
  )

  [String[]]$existingPathsUser = Get-EnvPathsArr('User')

  $NewPathsDiff = Compare-Object -ReferenceObject $existingPathsUser -DifferenceObject $NewPaths | `
    Where-Object SideIndicator -eq '=>' | `
    Select-Object -ExpandProperty InputObject

  if ($NewPathsDiff.Count -eq 0) {
    Write-Debug "[Add-UserPaths]: Paths ``$NewPaths`` already present, no changes needed."    
    return
  }

  $newEnvTargetUser = ($existingPathsUser + $NewPathsDiff) -join ';'

  Write-Debug "[Add-UserPaths]: Adding the following paths to user %PATH%:`n- $($NewPathsDiff -join "`n- ")`n"

  if (${Dry-Run} -eq $false) {
    [Environment]::SetEnvironmentVariable("Path", "$newEnvTargetUser", [System.EnvironmentVariableTarget]::User)
  }
  else {
    Write-Verbose "DRY-RUN: Setting User PATH to $newEnvTargetUser"
  }
}

##
##  Folders
##

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

##
## Font
##

function Install-Font() {
  param(
    [string]$SourcePath
  )
  (New-Object -ComObject Shell.Application).Namespace(0x14).CopyHere($SourcePath, 0x14);
}

##
## Misc
##

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

function Install-ModuleIfNotPresent {
  param(
    [string]$ModuleName
  )

  if (!(get-module $ModuleName -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-Module $ModuleName
  }
}

function UnderscroreTo-HashTable() {
  <#
  .SYNOPSIS
  An internal function to generate dynamic parameters based on the YAML object's members, and pass them through to the next PowerShell function.
  .DESCRIPTION
  This function takes an object and converts it to a hashtable, prepending an underscore to each key.
  .PARAMETER InputList
  The keys of the yaml object that will be converted to hashtable
  .PARAMETER Include
  An array of keys to include in the output hashtable. If specified, only keys in this array will be included.
  .PARAMETER Exclude
  An array of keys to exclude from the output hashtable if they are present in the input object.
  .EXAMPLE
  UnderscroreTo-HashTable -InputList $yaml -Include @("Name", "Version")
  #>
  param(
    [Parameter(Mandatory = $true)][System.Collections.Arraylist]$InputList,
    [System.Array]$Include = @(),
    [System.Array]$Exclude = @()
  )

  [System.Collections.Hashtable]$new = @{}

  Write-Debug "INputList= $InputList"
  Write-Debug "Keys= $($InputList.GetEnumerator())"

  foreach ($k in $InputList.GetEnumerator()) {
    Write-Debug "Reading $($k.Name)"

    if ( $PSBoundParameters.ContainsKey('Include') -and $k.Name -notin $Include) {
      Write-Debug "Key $($k.Name) not in Include list, skipping."
      continue
    }
    if ($Exclude -icontains $k.Name) {
      Write-Debug "Key $($k.Name) is in Exclude list, skipping."
      continue
    }

    $new.Add("_$($k.Name)", $k.value)
    Write-Debug "Setting _$($k.Name) = $($k.value)"
  }

  return $new
}


###
###  High Level Functions
###

function Install-Dependencies {
  Install-ModuleIfNotPresent 'PowerShell-YAML'
  Install-ModuleIfNotPresent 'PSMenu'
}

function Install-LightSync {
  $packages = Get-ChildItem "$PSScriptRoot/packages/*.yaml"
  $packages = $packages | Where-Object { $_.Name -ne "template.yaml" } # Exclude template.yaml
  
  $InitialSelection = Get-LightSyncPackageNames
  if (!$InitialSelection) { 
    # Select all packages by default
    $InitialSelection = @(0..$packages.Length) 
  }
  else {
    # Compare $packages with $InitialSelection and create an array of the common indexes
    # ie load the previously selected packages in the UI
    $InitialSelection = $packages | Where-Object { $InitialSelection -contains $_.Name } | ForEach-Object { $packages.IndexOf($_) }    
  }
  
  $Selection = Show-Menu -MenuItems $packages -MultiSelect -InitialSelection $InitialSelection -MenuItemFormatter { $args | Select -ExpandProperty Name }
  
  # Save new config in registry
  Set-LightSyncPackageNames -PackageNames $Selection.Name

  $LSDriveObj = Get-LighSyncDrivePath
  $defaultValue = $LSDriveObj.DrivePath
  $ValueType = $LSDriveObj.Status
  $prompt = Read-Host "Select LightSync drive and path (${ValueType}: $($defaultValue))"
  $prompt = ($defaultValue, $prompt)[[bool]$prompt]
  $LightSyncDrive = $prompt  
}

function Get-LighSyncDrivePath {
  <#
  .SYNOPSIS
  Get the LightSync virtual drive path from the registry  
  #>
  $RegPath = "$LSDREG\Drive"
  $DrivePath = Get-RegValue -FullPath $RegPath -ErrorAction 'SilentlyContinue'
  $Status = 'current'
  if (!$DrivePath) {
    $DrivePath = 'N:\Tools'
    $Status = 'default'
  }
  return @{
    DrivePath = $DrivePath
    Status    = $Status
  }
}

function Set-LightSyncDrivePath {
  <#
  .SYNOPSIS
  Set the LightSync virtual drive path in the registry
  #>
  param(
    [string]$DrivePath
  )
  $RegPath = "$LSDREG\Drive"
  Set-RegValue -FullPath $RegPath -Value $DrivePath -Type String -Force
}

function Get-LightSyncPackageNames {
  $RegPath = "$LSDREG\Packages"
  $Selection = Get-RegValue -FullPath $RegPath -ErrorAction SilentlyContinue
  return $Selection
}

function Set-LightSyncPackageNames {
  <#
  .SYNOPSIS
  Set the list of packages that the user has selected for syncing on this computer.
  #>
  param(
    [string[]]$PackageNames
  )
  $RegPath = "$LSDREG\Packages"
  Set-RegValue -FullPath $RegPath -Value $PackageNames -Type MultiString -Force
}

function Install-LightSyncDrive {
  <#
  .SYNOPSIS
  Deploy the script that will mount the Virtal Drive at startup
  Why is a virtual drive needed?
  The dropbox sync folder path can vary on different computer. Sometimes it's on the D: drive, sometimes is My Documents.
  Some portable apps get upset by this, especially those in .paf format.
  #>
  $SubstFile = "$STARTUP\subst-lightsync.bat"
  # Get the drive letter of a path:
  $LightSyncDrive = Get-LighSyncDrivePath -replace '^(.*:).*', '$1'
  $DropboxPath = Get-DropboxInstallPath
  if (!(Test-Path $SubstFile)) {
    $formatText = @"
    subst $LightSyncDrive $DropboxPath
    timeout 2
"@
    Set-Content $SubstFile -Value $formatText
  }

  if (!((Test-Path 'M:') -and (Test-Path 'N:'))) {
    &$SubstFile
  } 
}

function TemplateStr {
  <#
  .SYNOPSIS
  Replace placeholders in a string with values
  {PkgNane} = Name of package, ie the .yaml file without the extension
  {PkgPath} = {DbxRoot}\{PkgName}, eg. N:\Tools\7-zip
  {DbxRoot} = LightSyncDrive root path, eg. N:\Tools
  #>
  param(
    # Nullable
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$InputString,
    [Parameter(Mandatory = $true)][string]$PackageName
  )
  $NewString = $InputString `
    -replace '{PkgName}', $PackageName `
    -replace '{PkgPath}', "$LIGHTSYNCROOT\$PackageName" `
    -replace '{DbxRoot}', "$LIGHTSYNCROOT" `
    -replace '{LSRoot}', "$LIGHTSYNCROOT" `
    -replace '{LightSyncRoot}', "$LIGHTSYNCROOT" `
    -replace '/', '\'
  return $NewString
}

function Update-Shortcuts() {
  param(
    [Parameter(Mandatory = $true)][string]$PackageName,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][System.Collections.Generic.List`1[System.Object]]$Tasks
  )

  foreach ($task in $Tasks) {

    $ParentPath = switch ($task.Parent) {
      # Wshshell SpecialFolders
      "Programs-DBX" { [environment]::getfolderpath("Programs") + "\LightSync"; break }
      "Startup" { [environment]::getfolderpath("Startup"); break }
      default { [environment]::getfolderpath("Programs") + "\LightSync"; break }
    }

    $LinkPath = "${ParentPath}\$(TemplateStr -PackageName $PackageName -InputString $task.Name ) LightSync.lnk"

    $StartIn = switch ($task.StartIn) {
      $null { Split-Path -Path (TemplateStr -PackageName $PackageName -InputString $task.Target) } # Start in the Target Exe's folder by default
      default { TemplateStr -PackageName $PackageName -InputString $task.StartIn }
    }
  
    $Target = TemplateStr -PackageName $PackageName -InputString $task.Target

    $IconPath = switch -regex ($task.Icon) {
      "^$" { 
        # Use the target exe's icon by default        
        "$Target,0" 
      }
      ",\d+$" { 
        # Icon path already has a trailing `,0`
        TemplateStr -InputString $_ -PackageName $PackageName 
      }
      default { 
        # Append trailing `,0` if only icon file was specified
        "$(TemplateStr -InputString $_ -PackageName $PackageName ),0"
      } 
    }

    $Params = $task.Params

    $WindowStyle = switch ($task.WindowStyle) {
      $null { "Default" }
      default { $_ }
    }

    $Unrecognized = $task.keys | Where-Object { $_ -notin @('name', 'target', 'startin', 'params', 'icon', 'assoc', 'assocIcon', 'assocparam') }
    if ($Unrecognized) {
      Write-Warning "Unrecognized keys in task $($task.Name): $Unrecognized"
    }

    Write-Debug "[Update-Shortcuts]: [New-Shortcut]: LinkPath: $LinkPath, Target: $Target, Params: $Params, StartIn: $StartIn, IconPath: $IconPath, WindowStyle: $WindowStyle"
    New-Shortcut `
      -LnkPath  $LinkPath `
      -TargetExe $Target `
      -Arguments $Params `
      -WorkingDir $StartIn `
      -IconPath $IconPath `
      -WindowStyle $WindowStyle
  }
}


function Get-LightSyncPackageData {
  <#
  Get the package config from Get-LightSyncPackageNames, and load those yaml files into a hashtable with Get-Conent and ConvertFrom-Yaml.
  Alternatively, a custom package file can be specified using $PackageFile

  .PARAMETER Transpose
  Transpose the data into a [PSCustomObject] that works better with Format-Table and Out-GridView
  #>
  param(
    [string]$PackageFile,
    [switch]${ConvertTo-Text},
    [switch]$Transpose,
    [switch]$YamlDump
  )

  if ($PackageFile) {
    $PackageFiles = $PackageFile
  }
  else {
    $PackageRoot = "${LIGHTSYNCROOT}\_Packages\packages"
    $PackageFiles = (Get-LightSyncPackageNames) -replace '^', "$PackageRoot\"
  }

  Write-Debug "[Get-LightSyncPackageData]: Retrieved Package Names: $PackageNames"
  $AllPackagesObj = @()
  $Index = 0
  $tindex = 0
  foreach ($PackageFile in $PackageFiles) {
    # Get filename without path and extension
    $PackageName = (Split-Path -Leaf $PackageFile) -replace '\.[^.]*$'

    # Create $PackageObj new hashtable
    $PackageObj = @()
    
    $PackageObj = Get-Content $PackageFile | ConvertFrom-Yaml
    foreach ($TaskType in $PackageObj.Keys) {
      $TaskData = $PackageObj[$TaskType]
      if ($TaskData -isnot [System.Collections.Generic.List`1[System.Object]]) {
        continue
      }
      foreach ($Action in $TaskData) {
        if ($Action -isnot [System.Collections.Hashtable]) {
          continue
        }    
        # Adding metadata to the task objects
        $Action.Add("PkgName", $PackageName)
        $Action.Add("PkgPath" , "${LIGHTSYNCROOT}\$PackageName" )
        $Action.Add("tindex" , $tindex)
        $tindex++

      }
    }
    $PackageObj.Add("PkgName", $PackageName)
    $PackageObj.Add("PkgPath" , "${LIGHTSYNCROOT}\$PackageName" )
    $PackageObj.Add("Index", $Index)

    $Index++
    $AllPackagesObj += $PackageObj
  }

  if ($Transpose) {
    return $AllPackagesObj | ForEach-Object { [PSCustomObject]$_ } 
  }

  if (${ConvertTo-Text}) {
    $Keys = $AllPackagesObj.Keys | Sort-Object | Get-Unique
    $OrderedKeys = @('Index', 'PkgName', 'PkgPath')
    $OrderedKeys += @{Name = 'Shortcuts'; Expression = { $_.Shortcuts.name -join "`n" } }
    $OrderedKeys += @{Name = 'Assoc'; Expression = { $_.Shortcuts.assoc } }
    $OrderedKeys += @{Name = 'Paths'; Expression = { $_.paths -join "`n" } }
    $OrderedKeys += @{Name = 'Exec'; Expression = { $_.exec -join "`n" } }
    $OrderedKeys += @{Name = 'Reg'; Expression = { $_.reg.key -join "`n" } }
    #$OrderedKeys += @{Name = 'Files'; Expression = { $_.reg.key -join "`n" } }
    $OrderedKeysList = $OrderedKeys.Clone() | % { if ($_.Name) { $_.Name } else { $_ } }

    $RemainingKeys = (Compare-Object -ReferenceObject $Keys -DifferenceObject $OrderedKeysList |  Where-Object SideIndicator -eq '<=' | Select-Object -ExpandProperty InputObject)
    $OrderedKeys += $RemainingKeys
    
    return $AllPackagesObj | ForEach-Object { [PSCustomObject]$_ } | Select-Object -Property $OrderedKeys
  }

  if ($YamlDump) {
    $filename = "${env:TEMP}\LightSyncPackages-$(Get-Date -Format 'yyyyMMdd-HHmmss').yaml"
    $AllPackagesObj | ConvertTo-Yaml | Out-File $filename
    yq 'sort_keys(..)' -i $filename
    # Notepad++ detection
    if (Get-Command -ErrorAction Ignore -Type Application notepad++) {
      $OpenCmd = "notepad++"
    }
    else {
      Write-Debug "ConEmu is running, we can get the path from there."
      $OpenCmd = "notepad"
    }

    Write-Host "Opening $filename"
    Start-Process $filename -Wait
    return
  }

  return , $AllPackagesObj
}

function Update-FileAssocs {
  <#
  Function will iterate through the PSObject List to do the file associations.
  The following properties are expected:

  PkgName                   assoc target                                  name             assocparam assocIcon
  -------                   ----- ------                                  ----             ---------- ---------
  7-zip                     zip   {PkgPath}/7zFM.exe                      {PkgName}                   {PkgPath}/7z.dll,1
  FSViewer                  jpg   {PkgPath}/{PkgName}.exe                 {PkgName}
  LibreOfficePortable-7.4.2 xls   {PkgPath}/LibreOfficeCalcPortable.exe   {PkgName} Calc    -o "%1"
  Notepad++                 txt   {PkgPath}/notepad++.exe                 {PkgName}        {"%1"}

  #>
  
  param(
    [PsObject]$FileAssocs
  )

  foreach ($a in $FileAssocs) {
    $Target = TemplateStr -InputString $a.Target -PackageName $a.PkgName
    $assocIcon = TemplateStr -InputString $a.AssocIcon -PackageName $a.PkgName

    Write-Debug "[Update-FileAssocs]: Creating assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``"
    New-FileAssoc -Extension $a.assoc -ExePath $Target -Params $a.AssocParam -IconPath $assocIcon
    $pass = $null
  }
}

function Update-Paths {
  <#
  Update user %PATH% variables
  TODO - Implement removal of paths
  #>
  param(
    [PsObject]$Paths
  )

  $AddPaths = $Paths | Where-Object { $_.state -eq 'present' } | ForEach-Object { TemplateStr -InputString $_.Path -PackageName $_.PkgName }
  $RemovePaths = $Paths | Where-Object { $_.state -eq 'absent' } | ForEach-Object { TemplateStr -InputString $_.Path -PackageName $_.PkgName }

  if ($AddPaths) {
    Write-Debug "[Update-Paths]: Adding paths: $AddPaths"
    Add-UserPaths -NewPaths $AddPaths
  }

  if ($RemovePaths) {
    Write-Debug "[Update-Paths]: Removing paths: $RemovePaths - TBC"
  }
}

Function Update-Regs {
  <#
  data                                             type   key                                                                         PkgPath                 name                          PkgName        tindex
  ----                                             ----   ---                                                                         -------                 ----                          -------        ------
  {PkgPath}/App/ConEmu/ConEmu.exe                  String HKEY_CURRENT_USER\SOFTWARE\Classes\directory\shell\ConEmu DBX Here          N:\Tools\ConEmuPortable Icon                          ConEmuPortable      2
  "{PkgPath}/ConEmuPortable.exe" -Dir "%1"         String HKEY_CURRENT_USER\SOFTWARE\Classes\directory\shell\ConEmu DBX Here\command  N:\Tools\ConEmuPortable                               ConEmuPortable      3
  1                                                DWord  HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer                          N:\Tools\MyTools        DisableSearchBoxSuggestions   MyTools            16
  1                                                DWord  HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer                          N:\Tools\MyTools        ShowRunAsDifferentUserInStart MyTools            17
  #>

  param(
    [PsObject]$Regs
  )
  
  foreach ($r in $Regs) {
    $Key = TemplateStr -InputString $r.key -PackageName $r.PkgName
    $Value = TemplateStr -InputString $r.value -PackageName $r.PkgName
    $Type = TemplateStr -InputString $r.type -PackageName $r.PkgName
    $Data = TemplateStr -InputString $r.data -PackageName $r.PkgName

    Write-Debug "[Update-Regs]: Creating registry key: $Key"
    Set-RegValue -FullPath "${Key}\${Value}" -Value $Data -Type $Type -Force 
  }
}

function Update-Fonts {
  param(
    [PsObject]$Fonts
  )

  foreach ($f in $Fonts) {
    $Path = TemplateStr -InputString $f.FontPath -PackageName $f.PkgName
    Write-Debug "[Update-Fonts]: Installing font: $FontPath"
    Install-Font SourcePath $FontPath
  }
}

function Invoke-LightSync {
  param(
    [string]$PackageFile
  )

  $packages = Get-LightSyncPackageData -PackageFile $PackageFile
  Write-Debug "[Invoke-LightSync]: Retrieved Packages: $($packages | ConvertTo-Yaml)"
  # Isnullorempty
  if (!([string]::IsNullOrEmpty($Action))) {
    $packages = @{ $Action = ($packages | Where-Object { $_[$Action] }) }
  }
  foreach ($package in $packages) {
    $tasks = $package.Keys | where { $_ -notin @('PkgName', 'PkgPath') }
    Write-Debug "[Invoke-LightSync]: Tasks for $($package.PkgName): $tasks"
    foreach ($task in $tasks) {
      Write-Debug "[Invoke-LightSync]: >>>> Running task $task for $($package.PkgName) : $($package.$task)"
      switch ($task) {
        "shortcuts" {
          Update-Shortcuts `
            -PackageName $package.PkgName `
            -PackagePath $package.PkgPath `
            -Tasks $package.shortcuts

          $Assocs = @();
          # Expand the Assocs so that each one is a separate object
          # TODO - This can go in load function
          $package.shortcuts | Where-Object assoc | ForEach-Object { 
            $app = $_; $_.assoc | ForEach-Object { 
              $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app))
              $temp.assoc = $_; $Assocs += $temp 
            } 
          }

          $package += @{ Assocs = $Assocs }

          Update-FileAssocs -FileAssocs $Assocs
          $pass = $null
        }
        "paths" {
          # Expand array paths into dictionaries
          # TODO - This can go in load function 
          $Paths = @();
          foreach ($path in $package.paths) {
            if ( $path -is [string]) {
              $path = @{ 
                Path    = $path; 
                State   = 'present'
                PkgName = $package.PkgName
                PkgPath = $package.PkgPath
              }
            }
            $Paths += $path
          }

          Update-Paths -Paths $Paths
        }
        "reg" {
          $Regs = $package.reg
          Update-Regs -Regs $Regs
        }
        "fonts" {
          $Fonts = $package.fonts
          Update-Fonts -Fonts $Fonts
        }
      }
    }
  }
}
