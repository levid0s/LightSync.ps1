###
###  Low Level Functions
###    ie do stuff with the OS
###

function Write-DebugLog {
  param(
    [string]$Message
  )
  $Caller = (Get-PSCallStack)[1].Command
  # Get depth of call. 0 = main script, 1 = Helper ps1 , 2 = Write-DebugLog
  # Any negative value make to 0
  $Depth = 0, ((Get-PSCallStack).Count - 3) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum  # Main script is 0
  
  if (!$DEBUGDEPTH) {
    # Default value if not set via global var
    $DEBUGDEPTH = 2
  }

  if ($Depth -gt $DEBUGDEPTH) { return }
  if (!$DEBUGDEPTH) { $MaxDepth = 4 * 2 }
  else { $MaxDepth = $DEBUGDEPTH * 2 }

  $FrontPadChar = '>'
  $FrontPadVal = $Depth * 2
  $FrontPadding = $FrontPadChar * $FrontPadVal
  # $FrontPadding = $FrontPadding.PadRight($MaxDepth, ' ')
  $MidPadChar = '>'
  $MidPadVal = $Depth * 0
  $MidPadding = $MidPadChar * $MidPadVal + ' ' * [math]::Sign($MidPadVal)

  Write-Debug "${FrontPadding} [ ${Caller} ]: ${MidPadding}${Message}"
}

function IsAdmin {
  <#
  Returns True if the script is running with elevated privileges
  #>
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)  
}

function Invoke-SHChangeNotify {
  <#
  Function to call SHChangeNotify, which is used to notify the shell of changes.
  Can be used to refresh icons after an assoc change, instead of restarting Explorer.
  https://stackoverflow.com/questions/9986869/force-the-icons-on-the-desktop-to-refresh-after-deleting-items-or-stop-an-item
  #>
  $code = @'
  [System.Runtime.InteropServices.DllImport("Shell32.dll")] 
  private static extern int SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);

  public static void Refresh()  {
      SHChangeNotify(0x8000000, 0x1000, IntPtr.Zero, IntPtr.Zero);    
  }
'@

  Add-Type -MemberDefinition $code -Namespace WinAPI -Name Explorer 
  [WinAPI.Explorer]::Refresh()
}

###
###  Registry Functions
###

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
  $Value = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction $ErrorAction | Select-Object -ExpandProperty $Name

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
    if (!(Test-Path -LiteralPath $Path)) {
      New-Item -Path $Path -Force      
    }
  }

  switch -wildcard ($Type) {
    "*String" { $ValueConv = $Value }
    'Binary' { Throw "Set-RegValue -Type Binary : Not implemented" }
    'DWord' { $ValueConv = [System.Convert]::ToUInt32($Value[0]) }
    'QWord' { $ValueConv = [System.Convert]::ToUInt64($Value[0]) }
  }
  
  $CheckValues = (Get-ItemProperty -LiteralPath $Path).PSObject.Properties
  if ($CheckValues.Name -contains $Name) {
    if ($CheckValues[$Name].Value -eq $ValueConv) {
      Write-DebugLog "Value already set: $Path\$Name = $ValueConv ($Type)"
      Return
    }
  }
  New-ItemProperty -LiteralPath $Path -Name $Name -Value $ValueConv -PropertyType $Type -Force | Out-Null
  Write-DebugLog "Writing to registry: $Path\$Name = $ValueConv ($Type)"
}


##
##  Shortcuts
##

function New-Shortcut() {
  <#
  .PARAMETER Force
  Overwrite destination if already exists.
  TODO - Implement Force for non-unicode shortcuts
  #>

  param(
    [Parameter(Mandatory = $true)][string]$LnkPath,
    [Parameter(Mandatory = $true)][string]$TargetExe,
    [string[]]$Arguments,
    [string]$WorkingDir,
    [string]$IconPath,
    [Parameter()][ValidateSet('Default', 'Minimized', 'Maximized')][string]$WindowStyle = 'Default',
    [switch]$Force
  )

  if ((Test-Path -LiteralPath $LnkPath) -and !$Force) {
    Write-DebugLog "Link already exists, exiting."
    Return # "AlreadyExists"
  }

  if ($Force) {
    $ForceParam = @{Force = $null }
  }
  else {
    $ForceParam = @{ }
  }

  $bitWindowStyle = @{
    Default   = 1;
    Maximized = 3;
    Minimized = 7
  }

  $ParentPath = Split-Path $LnkPath -Parent
  if (!(Test-Path $ParentPath)) {
    New-Item -Path $ParentPath -ItemType Directory -Force
  }

  $nonASCII = "[^\x00-\x7F]"
  $HasUnicode = $LnkPath -cmatch $nonASCII

  if ($HasUnicode) {
    $RealLnkPath = $LnkPath
    $LnkPath = "$env:TEMP\$(New-Guid).lnk"
    Write-DebugLog "$RealLnkPath has Unicode characters. Temp file is: $LnkPath"
  }

  if ($Arguments) {
    Write-DebugLog "Arguments supplied: $Arguments"
  }
  $WshShell = New-Object -comObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($LnkPath)
  $Shortcut.TargetPath = $TargetExe
  $Shortcut.Arguments = $Arguments -join " "

  if ($IconPath) {
    $Shortcut.IconLocation = $IconPath
  }
  
  $Shortcut.WorkingDirectory = $WorkingDir
  $Shortcut.WindowStyle = $bitWindowStyle[$WindowStyle]
  $Shortcut.Save()

  if ($HasUnicode) {
    Move-Item -Path $LnkPath -Destination $RealLnkPath @ForceParam
    Write-DebugLog "Moved $LnkPath to $RealLnkPath"
  }
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

  $Extension = $Extension.ToLower() -replace '^\.', '' # Remove traling dot if supplied by accident

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

function New-FileAssocExt {
  <#
  .SYNOPSIS
  New File Assoc *EXTENDED* function; meaning an app registration is also created, eg. 7-Zip.zip
  Useful when multiple file types are associated with the same app; but they get different icons assigned.
  .PARAMETER Extension
  File extension for which to register the app association. Do not include the dot. Eg: 'zip', 'jpeg'
  .PARAMETER ExePath
  Path to the executable that would open this file type
  .PARAMETER Params
  Any parameters that should be passed to the executable. %1 will be replaced with the file path that the user wants to open.
  .PARAMETER IconPath
  Path to the icon that should be used for this file type.
  .PARAMETER Description
  Description of the file type. This will be displayed in the "Open with" dialog.
  .PARAMETER AppRegSuffix
  Suffix to append to the app registration name. Eg: tmp -> 7-Zip_tmp.zip
  .PARAMETER Force
  Force will remove the existing default association for this file type.
  #>
  # Note to self: Past user choices are stored here:
  # HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts
  param(
    [Parameter(Mandatory = $true)][string]$Extension,
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $false)][string]$Params,
    [Parameter(Mandatory = $false)][string]$IconPath,
    [Parameter(Mandatory = $false)][string]$Description,
    [Parameter(Mandatory = $false)][string]$AppRegSuffix,
    [Parameter(Mandatory = $false)][switch]$Force
  )

  $Extension = $Extension.ToLower() -replace '^\.', '' # Remove traling dot if supplied by accident
  $AppName = (Get-Item $ExePath).BaseName
  if ($AppRegSuffix) { $AppRegSuffix = "_${AppRegSuffix}" }
  $AppRegName = "${AppName}${AppRegSuffix}.${Extension}"
  if ([string]::IsNullOrEmpty($Params)) { $Params = "`"%1`"" }
  $OpenCmd = "$ExePath $Params"

  $AppRegPath = "HKCU:\SOFTWARE\Classes\${AppRegName}\shell\open\command\(Default)"
  Set-RegValue -FullPath $AppRegPath -Value $OpenCmd -Type REG_SZ -Force

  if ($IconPath) {
    $IconRegKey = "HKCU:\SOFTWARE\Classes\${AppRegName}\DefaultIcon\(Default)"
    Set-RegValue -FullPath $IconRegKey -Value $IconPath -Type REG_SZ -Force
  }

  if ($Description) {
    $DescriptionPath = "HKCU:\SOFTWARE\Classes\${AppRegName}\(Default)"
    Set-RegValue -FullPath $DescriptionPath -Value $Description -Type REG_SZ -Force
  }

  $ExtRegPath = "HKCU:\SOFTWARE\Classes\.${Extension}\(Default)"
  Set-RegValue -FullPath $ExtRegPath -Value $AppRegName -Type REG_SZ -Force

  if ($Force) {
    $UserChoicePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${Extension}\UserChoice"
    if (Test-Path -LiteralPath $UserChoicePath) {
      Write-DebugLog "Removing existing user choice for file extension .${Extension}: ${UserChoicePath}"
      $TempFile = "$env:TEMP\RemoveUserChoice_${Extension}.reg"
      Write-DebugLog "Temp reg file: $TempFile"

      $UserChoiceDelReg = @"
Windows Registry Editor Version 5.00
[-HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${Extension}\UserChoice]
"@
      Set-Content $TempFile $UserChoiceDelReg -Force
      # This will elevate to admin at each schedule, not great.
      regedit /s $TempFile
      if ($DebugPreference -ne 'Continue') {
        Remove-Item $TempFile -Force
      }
      
    }
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
  .PARAMETER Paths
  Array of string representing paths to add to the user's %PATH% environment variable.
  .EXAMPLE
  Add-UserPaths -Paths 'C:\Program Files\Git\cmd', 'C:\Program Files\Git\usr\bin'
  #>

  param(
    [string[]]$Paths
  )

  [String[]]$existingPathsUser = Get-EnvPathsArr('User')

  $NewPathsDiff = Compare-Object -ReferenceObject $existingPathsUser -DifferenceObject $Paths | `
    Where-Object SideIndicator -eq '=>' | `
    Select-Object -ExpandProperty InputObject

  if ($NewPathsDiff.Count -eq 0) {
    Write-DebugLog "Paths ``$Paths`` already present, no changes needed."    
    return
  }

  $newEnvTargetUser = ($existingPathsUser + $NewPathsDiff) -join ';'

  if (${Dry-Run} -eq $true) {
    Write-Verbose "DRY-RUN: Setting User PATH to $newEnvTargetUser"
  }
  else {
    Write-DebugLog "Adding the following paths to user %PATH%:`n- $($NewPathsDiff -join "`n- ")`n"
    [Environment]::SetEnvironmentVariable("Path", "$newEnvTargetUser", [System.EnvironmentVariableTarget]::User)
  }
}

function Remove-UserPaths {
  <#
  .SYNOPSIS
  Remove paths from the USER scope PATH environment variable.
  .PARAMETER Paths
  The paths to remove from the user PATH environment variable.
  .EXAMPLE
  Remove-UserPaths -Paths @('C:\Program Files\Git\cmd', 'C:\Program Files\Git\usr\bin')
  #>

  param(
    [string[]]$Paths
  )

  [String[]]$existingPathsUser = Get-EnvPathsArr('User')

  $remainingPaths = Compare-Object -ReferenceObject $existingPathsUser -DifferenceObject $Paths | `
    Where-Object SideIndicator -eq '<=' | `
    Select-Object -ExpandProperty InputObject

  $removePaths = Compare-Object -ReferenceObject $existingPathsUser -DifferenceObject $installPaths -ExcludeDifferent -IncludeEqual | `
    Select-Object -ExpandProperty InputObject

  if ($removePaths.Count -gt 0) {
    $newUserEnvString = $newPaths -join ';'    

    Write-DebugLog "Removing the following paths from user %PATH%:`n- $($removePaths -join "`n- ")`n"
    Write-Verbose "[Remove-UserPaths]: Updating user %PATH% to:`n- $($remainingPaths -join "`n- ")`n"

    [Environment]::SetEnvironmentVariable("Path", "$newUserEnvString", [System.EnvironmentVariableTarget]::User)
  }
  else {
    Write-DebugLog "No paths to remove from user %PATH%."
  }
}

function Update-PathsInShell {
  <#
  .SYNOPSIS
  Refresh the PATH environment variable in the current shell.
  #>

  $pathsInRegistry = Get-EnvPathsArr -Scope All
  $pathsInShell = $env:PATH -split ';'

  $diff = Compare-Object -ReferenceObject $pathsInRegistry -DifferenceObject $pathsInShell

  if (!$diff) {
    Write-DebugLog "%PATH% in shell already up to date."
    return
  }

  Write-Verbose "Updates to %PATH% detected:`n`n $($diff | Out-String) `n"
  Write-DebugLog "Refreshing %PATH% in current shell.."
  $env:Path = $pathsInRegistry -join ';'
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
    Write-DebugLog "Contents of ${IniPath}:"
    Write-Verbose [String[]]$Content

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
    Install-Module $ModuleName -Scope CurrentUser
  }
}

function Get-ScriptPath {
  return $MyInvocation.MyCommand.Source
}

###
###  High Level Functions
###

function Register-LightSyncScheduledTask {
  param(
    [string]$ScriptPath
  )

  $TaskName = "LightSync.sh - $env:USERNAME"

  if (!($ScriptPath)) {
    Throw "This function must be run from a file, not from the console."
  }

  # Create wrapper vbs script so we can run the PowerShell script as hidden
  # https://github.com/PowerShell/PowerShell/issues/3028

  $vbsPath = "$env:LOCALAPPDATA\LightSync.sh\LightSyncTask.vbs"
  $vbsDir = Split-Path $vbsPath -Parent
  $vbsScript = @"
Dim shell,command
command = "powershell.exe -nologo -File $ScriptPath"
Set shell = CreateObject("WScript.Shell")
shell.Run command,0
"@

  if (!(Test-Path $vbsDir)) {
    New-Item -ItemType Directory -Path $vbsDir
  }

  Set-Content -Path $vbsPath -Value $vbsScript -Force

  Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue -OutVariable TaskExists

  $action = New-ScheduledTaskAction -Execute $vbsPath
  
  $t1 = New-ScheduledTaskTrigger -Daily -At 01:00
  $t2 = New-ScheduledTaskTrigger -Once -At 01:00 `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 55)
  $t1.Repetition = $t2.Repetition
    
  # $trigger = New-ScheduledTaskTrigger `
  #   -Once `
  #   -At (Get-Date) `
  #   -RepetitionInterval (New-TimeSpan -Minutes 15) `
  #   -RepetitionDuration ([System.TimeSpan]::MaxValue)
  if (!$TaskExists) {
    Register-ScheduledTask -Action $action -Trigger $t1 -TaskName $TaskName -Description "Light User Profile Syncing Project for user $env:USERNAME"
  }
  else {
    Set-ScheduledTask -TaskName $TaskName -Action $action -Trigger $t1
  }
  
}

function Install-Dependencies {
  Install-ModuleIfNotPresent 'PowerShell-YAML'
  Install-ModuleIfNotPresent 'PSMenu'
}

function Invoke-PackagesWizard {
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
  
  $Selection = Show-Menu -MenuItems $packages -MultiSelect -InitialSelection $InitialSelection -MenuItemFormatter { $args | Select-Object -ExpandProperty Name }
  
  # Save new config in registry
  Set-LightSyncPackageNames -PackageNames $Selection.Name

  $LSDriveObj = Get-LighSyncDrivePath
  $defaultValue = $LSDriveObj.DrivePath
  $ValueType = $LSDriveObj.Status
  $prompt = Read-Host "Select LightSync drive and path (${ValueType}: $($defaultValue))"
  $prompt = ($defaultValue, $prompt)[[bool]$prompt]
  Set-LightSyncDrivePath -DrivePath $prompt # TODO??
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
  $LightSyncDrive = (Get-LighSyncDrivePath).DrivePath -replace '^(.*:).*', '$1'
  $DropboxPath = Get-DropboxInstallPath
  $formatText = @"
    subst $LightSyncDrive $DropboxPath
    timeout 2
"@
  Set-Content $SubstFile -Value $formatText

  if (!((Test-Path 'M:') -and (Test-Path 'N:'))) {
    &$SubstFile
  } 
}

function Convert-ObjectToString {
  <#
  .SYNOPSIS
  Convert an object to an array of strings that can be displayed in the console or logs.
  Supports optional padding on the left.
  Supports some basic hastable expansion.
  .PARAMETER InputObject
  The object to convert to a string using the Out-String cmdlet.
  .PARAMETER PadCount
  The number of characters to pad form left
  .Parameter PadChar
  The character to use for padding
  #>
  param(
    [Parameter(ValueFromPipeline, Mandatory)][object]$InputObject,
    [Parameter(Mandatory = $false)][int]$PadCount = 0,
    [Parameter(Mandatory = $false)][char]$PadChar = ' '
  )

  begin {
    # initialize empty generic list
    $all = [System.Collections.Generic.List[Object]]::new()
  }

  process {
    # [string]$PSCmdlet.MyInvocation.ExpectingInput can be used to detect if input is coming from pipe or parameter
    if (!$InputObject) {
      continue
    }

    $all += $InputObject
  }

  end {
    if ($all[0] -is [hashtable]) {
      Write-DebugLog "[hashtable] detected"
      $all = $all | ForEach-Object { [PSCustomObject]$_ }
    }
    if ($all.Count -gt 0) {
      $all = $all | Format-Table
    }

    [string[]]$Result = (Out-String -InputObject $all) -split '\r?\n'
    for ($start = 0; [string]::IsNullOrEmpty($Result[$start]) ; $start++) {
      # Trace forward until the first non-empty string
    }
    for ($end = $Result.Count - 1; [string]::IsNullOrEmpty($Result[$end]) ; $end--) {
      # Trace back to the last non-empty string
    }
    # Discard empty strings
    $Result = $Result[$start..$end]
    $Result = $Result | ForEach-Object { [string]$PadChar * $PadCount + $_ }
    return $Result
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
      "Programs-DBX" { [environment]::getfolderpath("Programs") + "\$START_MENU_FOLDER"; break }
      "Startup" { [environment]::getfolderpath("Startup"); break }
      default { [environment]::getfolderpath("Programs") + "\$START_MENU_FOLDER"; break }
    }

    $LinkPath = "${ParentPath}\$(TemplateStr -PackageName $PackageName -InputString $task.Name ) $APP_SHORTCUT_SUFFIX.lnk"

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

    $Unrecognized = $task.keys | Where-Object { $_ -notin @('name', 'target', 'startin', 'params', 'icon', 'assoc', 'assocIcon', 'assocparam', 'tindex', 'PkgPath', 'PkgName') }
    if ($Unrecognized) {
      Write-Warning "Unrecognized keys in task $($task.Name): $Unrecognized"
    }

    Write-DebugLog "LinkPath: $LinkPath, Target: $Target, Params: $Params, StartIn: $StartIn, IconPath: $IconPath, WindowStyle: $WindowStyle"
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

  Write-DebugLog "Retrieved Package Names: $PackageNames"
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
    $OrderedKeysList = $OrderedKeys.Clone() | ForEach-Object { if ($_.Name) { $_.Name } else { $_ } }

    $RemainingKeys = (Compare-Object -ReferenceObject $Keys -DifferenceObject $OrderedKeysList |  Where-Object SideIndicator -eq '<=' | Select-Object -ExpandProperty InputObject)
    $OrderedKeys += $RemainingKeys
    
    return $AllPackagesObj | ForEach-Object { [PSCustomObject]$_ } | Select-Object -Property $OrderedKeys
  }

  if ($YamlDump) {
    $filename = "${env:TEMP}\LightSyncPackages-$(Get-Date -Format 'yyyyMMdd-HHmmss').yaml"
    $AllPackagesObj | ConvertTo-Yaml | Out-File $filename
    yq 'sort_keys(..)' -i $filename

    Write-Host "Opening $filename"
    Start-Process $filename -Wait
    return
  }

  return , $AllPackagesObj
}

function Update-FileAssocs {
  <#
  Function for processing `package.shortcuts.assoc` (not `package.assoc`)
  Iterates through the PSObject List to register the file associations.

  Data is expected in the following format:

  PkgName                   assoc target                                  name             assocParam assocIcon
  -------                   ----- ------                                  ----             ---------- ---------
  7-zip                     zip   {PkgPath}/7zFM.exe                      {PkgName}                   {PkgPath}/7z.dll,1
  FSViewer                  jpg   {PkgPath}/{PkgName}.exe                 {PkgName}
  FSViewer                  jpeg  {PkgPath}/{PkgName}.exe                 {PkgName}
  LibreOfficePortable-7.4.2 xls   {PkgPath}/LibreOfficeCalcPortable.exe   {PkgName} Calc    -o "%1"
  Notepad++                 txt   {PkgPath}/notepad++.exe                 {PkgName}        {"%1"}

  #>
  
  param(
    [PsObject]$FileAssocs
  )

  foreach ($a in $FileAssocs) {
    $Target = TemplateStr -InputString $a.Target -PackageName $a.PkgName
    $assocIcon = TemplateStr -InputString $a.AssocIcon -PackageName $a.PkgName

    Write-DebugLog "Creating assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``"
    New-FileAssoc -Extension $a.assoc -ExePath $Target -Params $a.AssocParam -IconPath $assocIcon
  }
}

function Update-FileAssocsExt {
  <#
  Function for processing `package.assoc` (not `package.shortcuts.assoc`)
  Iterates through the PSObject List to do the file associations.

  Data is expected in the following format:

  PkgName                   assoc target                                   assocParam assocIcon           description  force
  -------                   ----- ------                                   ---------- ---------           -----------  -----
  7-zip                     zip   {PkgPath}/7zFM.exe                                  {PkgPath}/7z.dll,1  Zip archive  true
  FSViewer                  jpg   {PkgPath}/{PkgName}.exe                 
  FSViewer                  jpeg  {PkgPath}/{PkgName}.exe                 
  LibreOfficePortable-7.4.2 xls   {PkgPath}/LibreOfficeCalcPortable.exe     -o "%1"
  Notepad++                 txt   {PkgPath}/notepad++.exe                  {"%1"}

  #>

  param(
    [PsObject]$FileAssocs
  )

  foreach ($a in $FileAssocs) {
    $Target = TemplateStr -InputString $a.Target -PackageName $a.PkgName
    $assocIcon = TemplateStr -InputString $a.AssocIcon -PackageName $a.PkgName

    Write-DebugLog "Creating assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``"
    New-FileAssocExt `
      -Extension $a.assoc `
      -ExePath $Target `
      -Params $a.AssocParam `
      -IconPath $assocIcon `
      -Description $a.Description `
      -AppRegSuffix "LSH" `
      -Force:$a.Force
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
    Write-DebugLog "Adding paths: $AddPaths"
    Add-UserPaths -Paths $AddPaths
  }

  if ($RemovePaths) {
    Write-DebugLog "Removing paths: $RemovePaths - TBC"
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
    $Name = TemplateStr -InputString $r.name -PackageName $r.PkgName
    $Type = TemplateStr -InputString $r.type -PackageName $r.PkgName
    $Data = TemplateStr -InputString $r.data -PackageName $r.PkgName

    if ($r.Admin -and !$ISADMIN) {
      Write-Warning "[Update-Regs]: Skipping registry key: $($r.key)\$($r.name) = $($r.data) ($($r.type)) - Admin required"
      continue
    }

    Write-DebugLog "Creating registry key: $Key\$Name = $Data ($Type)"
    Set-RegValue -FullPath "${Key}\${Name}" -Value $Data -Type $Type -Force 
  }
}

function Update-Fonts {
  param(
    [PsObject]$Fonts
  )

  foreach ($f in $Fonts) {
    $FontPath = TemplateStr -InputString $f.FontPath -PackageName $f.PkgName
    Write-DebugLog "Installing font: $FontPath"
    Install-Font SourcePath $FontPath
  }
}

function Invoke-LightSync {
  param(
    [string]$PackageFile
  )

  $packages = Get-LightSyncPackageData -PackageFile $PackageFile
  Write-Verbose "[Invoke-LightSync]: Retrieved Packages: $($packages | ConvertTo-Yaml)"
  # Isnullorempty
  if (!([string]::IsNullOrEmpty($Action))) {
    $packages = @{ $Action = ($packages | Where-Object { $_[$Action] }) }
  }
  foreach ($package in $packages) {
    $tasks = $package.Keys | Where-Object { $_ -notin @('PkgName', 'PkgPath') }
    Write-DebugLog "Tasks for $($package.PkgName): $tasks"
    foreach ($task in $tasks) {
      Write-DebugLog "Running task $task for $($package.PkgName) : $($package.$task)"
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
              # Make a full copy of the object
              $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app))
              $temp.assoc = $_; $Assocs += $temp 
            } 
          }

          # $package += @{ Assocs = $Assocs }

          Update-FileAssocs -FileAssocs $Assocs
        }
        "assocs" {
          # Root `package.assocs`, not the same as `package.shortcuts.assoc`
          $Assocs = @();
          $package.assocs | ForEach-Object {
            $app = $_; $_.assoc | ForEach-Object { # Expand each assoc into a separate element
              # Make a full copy of the object
              $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app))
              $temp.assoc = $_; $Assocs += $temp 
            }
          }

          Update-FileAssocsExt -FileAssocs $Assocs

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

$STARTUP = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$LSDREG = "HKEY_CURRENT_USER\SOFTWARE\LightSync"
$LIGHTSYNCROOT = (Get-LighSyncDrivePath).DrivePath
$ISADMIN = IsAdmin
$APP_SHORTCUT_SUFFIX = [char]0x26a1
# $APP_SHORTCUT_SUFFIX = "LSA"
$START_MENU_FOLDER = "LightSync.sh"
# $DEBUGDEPTH - to set externally for the level of logging to display