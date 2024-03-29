$ScriptRoot = $PSScriptRoot
if (!$ScriptRoot) {
  $ScriptRoot = Get-Location
}

. "$ScriptRoot/../../src/useful/ps-winhelpers/_PS-WinHelpers.ps1"
. "$ScriptRoot/experiments/Experiments.ps1"

###
###  High Level Functions
###

function Register-LightSyncScheduledTask {
  param(
    [string]$ScriptPath
  )

  if (!($ScriptPath)) {
    Throw 'This function must be run from a file, not from the console.'
  }

  $TaskName = "LightSync.sh - $env:USERNAME"

  Register-PowerShellScheduledTask `
    -ScriptPath $ScriptPath `
    -TaskName $TaskName `
    -TimeInterval 15
}


function Install-Dependencies {
  Install-ModuleIfNotPresent 'PowerShell-YAML'
  Install-ModuleIfNotPresent 'PSMenu'
}

function Invoke-PackagesWizard {
  $packages = Get-ChildItem "$PSScriptRoot/packages/*.yaml"
  $packages = $packages | Where-Object { $_.Name -ne 'template.yaml' } # Exclude template.yaml
  
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
      Write-DebugLog '[hashtable] detected'
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
    [Parameter(Mandatory = $true)][string]$PackageName,
    [switch]$ExpandString
  )
  $NewString = $InputString `
    -replace '{PkgName}', $PackageName `
    -replace '{PkgPath}', "$LIGHTSYNCROOT\$PackageName" `
    -replace '{DbxRoot}', "$LIGHTSYNCROOT" `
    -replace '{LSRoot}', "$LIGHTSYNCROOT" `
    -replace '{LightSyncRoot}', "$LIGHTSYNCROOT" `
    -replace '/', '\'

  if ($ExpandString) {
    $NewString = $ExecutionContext.InvokeCommand.ExpandString($NewString)
  }
  return $NewString
}

function Update-Shortcuts {
  param(
    [Parameter(Mandatory = $true)][string]$PackageName,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][System.Collections.Generic.List`1[System.Object]]$Tasks
  )

  foreach ($task in $Tasks) {
    $ParentPath = switch ($task.Parent) {
      # Wshshell SpecialFolders
      'Programs-DBX' { [environment]::getfolderpath('Programs') + "\$START_MENU_FOLDER"; break }
      'Startup' { [environment]::getfolderpath('Startup'); break }
      default { [environment]::getfolderpath('Programs') + "\$START_MENU_FOLDER"; break }
    }

    $LinkPath = "${ParentPath}\$(TemplateStr -PackageName $PackageName -InputString $task.Name ) $APP_SHORTCUT_SUFFIX.lnk"

    $StartIn = switch ($task.StartIn) {
      $null { Split-Path -Path (TemplateStr -PackageName $PackageName -InputString $task.Target) } # Start in the Target Exe's folder by default
      default { TemplateStr -PackageName $PackageName -InputString $task.StartIn }
    }
  
    $Target = TemplateStr -PackageName $PackageName -InputString $task.Target
    $IconPath = switch -regex ($task.Icon) {
      '^$' {
        if (Test-Path $target -ErrorAction SilentlyContinue) {
          if (!(Get-Item $target).PSIsContainer) {
            # Use the target exe's icon by default, if it's not a folder
            "$Target,0" 
          }
        }
      }
      ',\d+$' { 
        # Icon path already contains the index
        TemplateStr -InputString $_ -PackageName $PackageName 
      }
      default { 
        # Append trailing `,0` if only an icon or binary was specified
        "$(TemplateStr -InputString $_ -PackageName $PackageName ),0"
      } 
    }

    $iconFilePath, $iconIndex = $IconPath -split ','
    if ([System.IO.Path]::IsPathRooted($iconFilePath)) {
      $iconFilePath = Get-RealPath -Path $iconFilePath
    }
    if ($iconIndex) {
      $iconIndex = ",$iconIndex"
    }
    $IconPath = "${iconFilePath}${iconIndex}"

    $Params = @()
    foreach ($p in $task.params) {
      if ($p -match '{LSRoot}|{PkgName}|{PkgPath}') {
        $Params += TemplateStr -PackageName $PackageName -InputString $p
      }
      else {
        $Params += $p
      }
    }

    $WindowStyle = switch ($task.WindowStyle) {
      $null { 'Default' }
      default { $_ }
    }

    $KnownTasks = @(
      'name', 
      'target', 
      'startin', 
      'params', 
      'icon', 
      'assoc', 
      'assocIcon', 
      'assocparam', 
      'tindex', 
      '_PkgPath', 
      '_PkgName',
      'friendlyAppName',
      'parent'
    )
    $Unrecognized = $task.keys | Where-Object { $_ -notin $KnownTasks }
    if ($Unrecognized) {
      Write-Warning "Unrecognized keys in task $($task.Name): $Unrecognized"
    }

    Write-DebugLog "LinkPath: $LinkPath, Target: $Target, Params: $Params, StartIn: $StartIn, IconPath: $IconPath, WindowStyle: $WindowStyle"
    try {
      $result = New-Shortcut `
        -LnkPath $LinkPath `
        -TargetExe $Target `
        -Arguments $Params `
        -WorkingDir $StartIn `
        -IconPath $IconPath `
        -WindowStyle $WindowStyle

      if ($result) {
        Write-DebugLog "Created shortcut $LinkPath" -LogLevel Info
      }
    }
    catch {
      Write-Error "Failed to create shortcut ${LinkPath}: $_"
    }
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
    $PackageNames = Split-Path $PackageFile -Leaf
  }
  else {
    $PackageRoot = "${LIGHTSYNCROOT}\_Packages\packages"
    $PackageNames = Get-LightSyncPackageNames
    $PackageFiles = $PackageNames -replace '^', "$PackageRoot\"
  }

  Write-DebugLog "Retrieved package names: $($PackageNames -join ', ')"
  $AllPackagesObj = @()
  $_Index = 0
  $tindex = 0
  foreach ($PackageFile in $PackageFiles) {
    # Get filename without path and extension
    $PackageName = (Split-Path -Leaf $PackageFile) -replace '\.[^.]*$'

    # Create $PackageObj new hashtable
    $PackageObj = @()
    
    try {
      $PackageObj = Get-Content $PackageFile -ErrorAction Stop | ConvertFrom-Yaml
    }
    catch {
      Continue
    }
    # | ConvertFrom-Yaml
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
        $Action.Add('_PkgName', $PackageName)
        $Action.Add('_PkgPath' , "${LIGHTSYNCROOT}\$PackageName" )
        $Action.Add('tindex' , $tindex)
        $tindex++

      }
    }
    $PackageObj.Add('_PkgName', $PackageName)
    $PackageObj.Add('_PkgPath' , "${LIGHTSYNCROOT}\$PackageName" )
    $PackageObj.Add('_Index', $_Index)

    $_Index++
    $AllPackagesObj += $PackageObj
  }

  if ($Transpose) {
    return $AllPackagesObj | ForEach-Object { [PSCustomObject]$_ } 
  }

  if (${ConvertTo-Text}) {
    $Keys = $AllPackagesObj.Keys | Sort-Object | Get-Unique
    $OrderedKeys = @('_Index', '_PkgName', '_PkgPath')
    $OrderedKeys += @{Name = 'Shortcuts'; Expression = { $_.Shortcuts.name -join "`n" } }
    $OrderedKeys += @{Name = 'Assoc'; Expression = { $_.Shortcuts.assoc } }
    $OrderedKeys += @{Name = 'Paths'; Expression = { $_.paths -join "`n" } }
    $OrderedKeys += @{Name = 'Exec'; Expression = { $_.exec -join "`n" } }
    $OrderedKeys += @{Name = 'Reg'; Expression = { $_.reg.key -join "`n" } }
    #$OrderedKeys += @{Name = 'Files'; Expression = { $_.reg.key -join "`n" } }
    $OrderedKeysList = $OrderedKeys.Clone() | ForEach-Object { if ($_.Name) { $_.Name } else { $_ } }

    $RemainingKeys = (Compare-Object -ReferenceObject $Keys -DifferenceObject $OrderedKeysList | Where-Object SideIndicator -EQ '<=' | Select-Object -ExpandProperty InputObject)
    $OrderedKeys += $RemainingKeys
    
    return $AllPackagesObj | ForEach-Object { [PSCustomObject]$_ } | Select-Object -Property $OrderedKeys
  }

  if ($YamlDump) {
    $filename = "${env:TEMP}\LightSyncPackages-$(Get-Date -Format 'yyyyMMdd-HHmmss').yaml"
    $AllPackagesObj | ConvertTo-Yaml | Out-File $filename
    yq 'sort_keys(..)' -i $filename

    Write-DebugLog "Opening $filename" -LogLevel Verbose
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

  _PkgName                   assoc target                                  name             assocParam assocIcon
  -------                   ----- ------                                  ----             ---------- ---------
  7-zip                     zip   {_PkgPath}/7zFM.exe                      {_PkgName}                   {_PkgPath}/7z.dll,1
  FSViewer                  jpg   {_PkgPath}/{_PkgName}.exe                 {_PkgName}
  FSViewer                  jpeg  {_PkgPath}/{_PkgName}.exe                 {_PkgName}
  LibreOfficePortable-7.4.2 xls   {_PkgPath}/LibreOfficeCalcPortable.exe   {_PkgName} Calc    -o "%1"
  Notepad++                 txt   {_PkgPath}/notepad++.exe                 {_PkgName}        {"%1"}

  #>
  
  param(
    [PsObject]$FileAssocs
  )

  foreach ($a in $FileAssocs) {
    $Target = TemplateStr -InputString $a.Target -PackageName $a._PkgName
    $assocIcon = TemplateStr -InputString $a.AssocIcon -PackageName $a._PkgName
    $FriendlyAppName = TemplateStr -InputString $a.FriendlyAppName -PackageName $a._PkgName
    Write-DebugLog "Creating assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``"
    try {
      $result = New-FileAssoc -Extension $a.assoc -ExePath $Target -Params $a.AssocParam -IconPath $assocIcon -FriendlyAppName $FriendlyAppName
      if ($result) {
        Write-DebugLog "Updated assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to update Assoc: $_" -LogLevel Error
    }
  }
}

function Update-FileAssocsExt {
  <#
  Function for processing `package.assoc` (not `package.shortcuts.assoc`)
  Iterates through the PSObject List to do the file associations.

  Data is expected in the following format:

  _PkgName                   assoc target                                   assocParam assocIcon           description  force  verb     verblabel
  -------                   ----- ------                                   ---------- ---------           -----------  -----  -------  -----
  7-zip                     zip   {_PkgPath}/7zFM.exe                                  {_PkgPath}/7z.dll,1  Zip archive  true   enqueue  Enqueue in Winamp
  FSViewer                  jpg   {_PkgPath}/{_PkgName}.exe                 
  FSViewer                  jpeg  {_PkgPath}/{_PkgName}.exe                 
  LibreOfficePortable-7.4.2 xls   {_PkgPath}/LibreOfficeCalcPortable.exe     -o "%1"
  Notepad++                 txt   {_PkgPath}/notepad++.exe                  {"%1"}

  #>

  param(
    [PsObject]$FileAssocs
  )

  foreach ($a in $FileAssocs) {
    $Target = TemplateStr -InputString $a.Target -PackageName $a._PkgName
    Write-DebugLog "New target: $Target" -LogLevel Verbose
    $FriendlyAppName = TemplateStr -InputString $a.FriendlyAppName -PackageName $a._PkgName
    $assocIcon = TemplateStr -InputString $a.AssocIcon -PackageName $a._PkgName
    $iconFilePath, $iconIndex = $assocIcon -split ','
    if ([System.IO.Path]::IsPathRooted($iconFilePath)) {
      $iconFilePath = Get-RealPath -Path $iconFilePath
    }
    if ($iconIndex) {
      $iconIndex = ",$iconIndex"
    }
    $assocIcon = "${iconFilePath}${iconIndex}"


    Write-DebugLog "Creating assoc for .$($a.assoc) -> ``$Target``, param: ``$($a.AssocParam)``"
    try {
      $result = New-FileAssocExt `
        -Extension $a.assoc `
        -ExePath $Target `
        -Params $a.AssocParam `
        -IconPath $assocIcon `
        -Description $a.Description `
        -FriendlyAppName $FriendlyAppName `
        -AppRegSuffix 'LSH' `
        -Verb $a.Verb `
        -VerbLabel $a.VerbLabel `
        -Force:$a.Force

      if ($result) {
        Write-DebugLog "Updated assoc for $($a.assoc) -> ``$Target`` : ``$($a.AssocParam)``" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to update AssocExt: $_" -LogLevel Error
    }
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

  $AddPaths = $Paths | Where-Object { $_.state -eq 'present' } | ForEach-Object { TemplateStr -InputString $_.Path -PackageName $_._PkgName }
  $RemovePaths = $Paths | Where-Object { $_.state -eq 'absent' } | ForEach-Object { TemplateStr -InputString $_.Path -PackageName $_._PkgName }

  if ($AddPaths) {
    Write-DebugLog "Adding paths: $AddPaths" -LogLevel Verbose
    try {
      $result = Add-UserPaths -Paths $AddPaths
      if ($result) {
        Write-DebugLog "Added paths: $AddPaths" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to add paths: $AddPaths`n$_" -LogLevel Error
    }
  }

  if ($RemovePaths) {
    Write-DebugLog "Removing paths: $RemovePaths - TBC"
  }
}

Function Update-Regs {
  <#
  data                                             type   key                                                                         _PkgPath                 name                          _PkgName        tindex
  ----                                             ----   ---                                                                         -------                 ----                          -------        ------
  {_PkgPath}/App/ConEmu/ConEmu.exe                  String HKEY_CURRENT_USER\SOFTWARE\Classes\directory\shell\ConEmu DBX Here          N:\Tools\ConEmuPortable Icon                          ConEmuPortable      2
  "{_PkgPath}/ConEmuPortable.exe" -Dir "%1"         String HKEY_CURRENT_USER\SOFTWARE\Classes\directory\shell\ConEmu DBX Here\command  N:\Tools\ConEmuPortable                               ConEmuPortable      3
  1                                                DWord  HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer                          N:\Tools\MyTools        DisableSearchBoxSuggestions   MyTools            16
  1                                                DWord  HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer                          N:\Tools\MyTools        ShowRunAsDifferentUserInStart MyTools            17
  #>

  param(
    [PsObject]$Regs
  )
  
  foreach ($r in $Regs) {
    $Key = TemplateStr -InputString $r.key -PackageName $r._PkgName
    $Name = TemplateStr -InputString $r.name -PackageName $r._PkgName
    if (!$r.State) {
      $r.State = 'present'
    }

    if ($r.State -eq 'absent' -and (Test-Path -Path $Key)) {
      Write-DebugLog "Removing registry value: $Key"
      try {
        $result = Remove-Item -Path $Key -Recurse -Force -ErrorAction Stop | Out-Null
        if ($result) {
          Write-DebugLog "Registry value removed: $Key" -LogLevel Info
        }
      }
      catch {
        Write-DebugLog "Failed to remove registry value: $Key`n$_" -LogLevel Error
      }
      continue
    }

    $Type = $r.Type
    if ($r.type -in @('String', 'ExpandString', 'REG_SZ', 'REG_EXPAND_SZ')) {
      $Data = TemplateStr -InputString $r.data -PackageName $r._PkgName
    }
    else {
      $Data = $r.data
    }

    # if ($r.Admin -and !$ISADMIN) {
    #   Write-Warning "[Update-Regs]: Skipping registry key: $($r.key)\$($r.name) = $($r.data) ($($r.type)) - Admin required"
    #   Continue
    # }

    Write-DebugLog "Creating registry value: $Key\$Name = $Data ($Type)"
    try {
      $result = Set-RegValue -FullPath "${Key}\${Name}" -Value $Data -Type $Type -Force 
      if ($result) {
        Write-DebugLog "Registry value created: $Key\$Name = $Data ($Type)" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to create registry value: $Key\$Name = $Data ($Type)" -LogLevel Error
    }
  }
}

function Update-RegsWild {
  param(
    [PsObject]$RegsWild
  )

  foreach ($r in $RegsWild) {
    $Key = TemplateStr -InputString $r.key -PackageName $r._PkgName
    $Name = TemplateStr -InputString $r.name -PackageName $r._PkgName
    $Type = $r.Type
    if ($Type -in @('String', 'ExpandString', 'REG_SZ', 'REG_EXPAND_SZ')) {
      $Data = TemplateStr -InputString $r.data -PackageName $r._PkgName
    }
    else {
      $Data = $r.data
    }

    Write-DebugLog "Creating registry value: $Key\$Name = $Data ($Type)"
    $keys = Get-Item -Path $key -ErrorAction SilentlyContinue
    foreach ($k in $keys) {
      Write-DebugLog "Name: $Name" -LogLevel Verbose
      if ($Name -match '\*') {
        # We're doing wildcard matching in Name also
        Write-DebugLog "COMMAND: `$Names = Get-ItemProperty -Path '$($k.PsPath)' -Name '$Name' -ErrorAction SilentlyContinue" -LogLevel Verbose
        $Names = Get-ItemProperty -Path $k.PsPath -Name $Name -ErrorAction SilentlyContinue
        $Names = $Names.PSObject.Members
        $Names = $Names | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSProvider', 'PSDrive') } | ForEach-Object { $_.Name }
        [string[]]$Paths = $Names | ForEach-Object { "$($k.Name)\$_" }
      }
      else {
        [string[]]$Paths = "$($k.Name)\$Name"
      }
      foreach ($p in $paths) {
        Write-Verbose "Creating registry value: $p = $Data ($Type)"
        try {
          $result = Set-RegValue -FullPath $p -Value $Data -Type $Type
          if ($result) {
            Write-DebugLog "Registry value created: $p = $Data ($Type)" -LogLevel Info
          }
        }
        catch {
          Write-DebugLog "Failed to create registry value: $p = $Data ($Type)" -LogLevel Error
        }  
      }
    }
  }
}

function Update-Fonts {
  param(
    [PsObject]$Fonts
  )

  foreach ($f in $Fonts) {
    $FontPath = TemplateStr -InputString $f.Path -PackageName $f._PkgName
    Write-DebugLog "Installing font: $FontPath"
    try {
      $result = Install-Font -SourcePath $FontPath
      if ($result) {
        Write-DebugLog "Installed font: $FontPath" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to install font: $FontPath`n$_" -LogLevel Error
    }
  }
}

function Update-ShellStaticVerbs {
  param(
    [PsObject]$ShellStaticVerbs
  )

  foreach ($v in $ShellStaticVerbs) {
    $target = TemplateStr -InputString $v.Target -PackageName $v._PkgName
    try {
      $result = Set-ShellStaticVerb -class $v.class -Verb $v.Verb -Target $target -Label $v.verblabel
      if ($result) {
        Write-DebugLog "Updated ShellStaticVerb: $($v.class) -> $($v.Verb) -> $target" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to update ShellStaticVerb: $($v.class) -> $($v.Verb) -> $target`n$_" -LogLevel Error
    }
  }
}

function Update-DropboxIgnore {
  param(
    [PsObject[]]$DropboxIgnore
  )

  foreach ($d in $DropboxIgnore) {
    $target = TemplateStr -InputString $d.target -PackageName $d._PkgName
    Write-DebugLog "Updating Dropbox ignore file: $target"
    try {
      $result = Set-DropboxIgnoredPath -Path $target -ErrorAction SilentlyContinue
      if ($result) {
        Write-DebugLog "Added path to Dropbox ignore: $target" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to add path to Dropbox ignore: $target`n$_" -LogLevel Error
    }
  }
}

function Update-DropboxOffline {
  param(
    [PsObject[]]$DropboxOffline
  )

  foreach ($d in $DropboxOffline) {
    $target = TemplateStr -InputString $d.Path -PackageName $d._PkgName
    Write-DebugLog "Updating Dropbox offline file: $target, mode: $($d.Mode)"
    try {
      $result = Set-DropboxItemOfflineMode -Path $target -Mode $d.Mode -ErrorAction SilentlyContinue
      if ($result) {
        Write-DebugLog "Updated Dropbox offline mode: $target, mode: $($d.Mode)" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to update Dropbox offline mode: $target, mode: $($d.Mode)`n$_" -LogLevel Error
    }
  }
}

function Update-RunOnce {
  param(
    [PsObject[]]$RunOnce,
    [switch]$Force
  )

  foreach ($r in $RunOnce) {
    $command = TemplateStr -InputString $r.command -PackageName $r._PkgName
    # Calculate Hash of the $command string
    $hash = Get-StringHash -String $command -HashAlgorithm MD5
    $regdata = Get-RegValue -FullPath "$LSDREG\RunOnceData\$hash" -ErrorAction SilentlyContinue
    if ($regdata -and !$force) {
      Write-DebugLog "This command was already done, skipping: $command"
      continue
    }
    $cmdArgs = @('/c')
    $cmdArgs += ($command -split ' ')
    Write-DebugLog "Executing command: $command"
    $exec = Start-Process 'cmd' -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru -ErrorAction Continue

    if ($exec.ExitCode -ne 0) {
      Write-DebugLog "RunOnce command failed: $command" -LogLevel Error
      return
    }

    Write-DebugLog "RunOnce command succeeded: $command" -LogLevel Info

    Set-RegValue -FullPath "$LSDREG\RunOnceData\$hash" -Value $command -Type String -Force | Out-Null
  }
}

function Update-Junctions {
  param(
    [PsObject[]]$Junctions
  )

  foreach ($j in $Junctions) {
    # Target is the real path
    $target = TemplateStr -InputString $j.target -PackageName $j._PkgName
    $target = $ExecutionContext.InvokeCommand.ExpandString($target)
    if (!(Test-Path $target)) {
      Write-DebugLog "Target doesn't exist: $target. Skipping." -LogLevel Error
      Continue
    }
    $target = Get-RealPath $target

    # Junction is the virtual path
    $junction = TemplateStr -InputString $j.link -PackageName $j._PkgName
    $junction = $ExecutionContext.InvokeCommand.ExpandString($junction)
    $junctionParent = Split-Path $junction -Parent
    if (!(Test-Path $junctionParent)) {
      Write-DebugLog "Junction parent doesn't exist: $junctionParent. Skipping." -LogLevel Error
      continue
    }
    $junctionLeaf = Split-Path $junction -Leaf
    $junctionParent = Get-RealPath $junctionParent
    $junction = "$junctionParent\$junctionLeaf"
    if (Test-Path $junction) {
      $jOld = Get-Item $junction
      if ($jOld.Target -eq $target) {
        Write-DebugLog "Junction already exists: $junction <- $target, skipping."
        Continue
      }
      if ($j.Force) {
        $junctionBackup = "$junction-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-DebugLog "Something already exists at the junction's path, moving it out of the way: $junction -> $junctionBackup" -LogLevel Info
        Rename-Item -Path $junction -NewName $junctionBackup
      }
      else {
        Write-DebugLog "Something already exists at the junction's path, skipping: $junction" -LogLevel Warning
        Continue
      }
    }

    Write-DebugLog "Creating junction: $junction <- $target"
    try {
      $result = New-Item -ItemType Junction -Path $junction -Target $target
      if ($result) {
        Write-DebugLog "Created junction: $junction <- $target" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to create junction: $junction <- $target`n$_" -LogLevel Error
    }
  }
}

function Update-Symlinks {
  param(
    [PsObject[]]$Symlinks
  )

  foreach ($s in $Symlinks) {
    # Target is the real path
    $target = TemplateStr -InputString $s.target -PackageName $s._PkgName
    $target = $ExecutionContext.InvokeCommand.ExpandString($target)
    if (!(Test-Path $target)) {
      Write-DebugLog "Target doesn't exist: $target. Skipping." -LogLevel Error
      Continue
    }
    $target = Get-RealPath $target

    # Symlink is the virtual path
    $symlink = TemplateStr -InputString $s.link -PackageName $s._PkgName
    $symlink = $ExecutionContext.InvokeCommand.ExpandString($symlink)
    $symlinkParent = Split-Path $symlink -Parent
    if (!(Test-Path $symlinkParent)) {
      Write-DebugLog "Symlink parent doesn't exist: $symlinkParent. Skipping." -LogLevel Error
      continue
    }
    $symlinkLeaf = Split-Path $symlink -Leaf
    $symlinkParent = Get-RealPath $symlinkParent
    $symlink = "$symlinkParent\$symlinkLeaf"
    if (Test-Path $symlink) {
      $sOld = Get-Item $symlink
      if ($sOld.Target -eq $target) {
        Write-DebugLog "Symlink already exists: $symlink <- $target, skipping."
        Continue
      }
      if ($s.Force) {
        $symlinkBackup = "$symlink-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-DebugLog "Something already exists at the symlink's path, moving it out of the way: $symlink -> $symlinkBackup" -LogLevel Info
        Rename-Item -Path $symlink -NewName $symlinkBackup
      }
      else {
        Write-DebugLog "Something already exists at the symlink's path, skipping: $symlink" -LogLevel Warning
        Continue
      }
    }

    Write-DebugLog "Creating symlink: $symlink <- $target"
    try {
      $result = New-Item -ItemType SymbolicLink -Path $symlink -Target $target
      if ($result) {
        Write-DebugLog "Created symlink: $symlink <- $target" -LogLevel Info
      }
    }
    catch {
      Write-DebugLog "Failed to create symlink: $symlink <- $target`n$_" -LogLevel Error
    }
  }
}

function Update-Files {
  param(
    [PsObject[]]$Files
  )

  foreach ($f in $Files) {
    Write-DebugLog "Processing: $($f.target)"
    if (!$f.State) { $f.State = 'present' }
    $f.Target = TemplateStr -InputString $f.Target -PackageName $f._PkgName -ExpandString

    if ($f.State -eq 'absent') {
      Write-DebugLog "Attempting to remove: $($f.target)" -LogLevel Verbose
      if (Test-Path $f.target -PathType Leaf) {
        try {
          Remove-Item -Path $f.target -Force
          Write-DebugLog "Removed file: $($f.target)." -LogLevel INFO
        }
        catch {
          Write-DebugLog -Message $_ -LogLevel Error
        }
      }
      else {
        Write-DebugLog "File already removed: $($f.target)" -LogLevel Verbose
        continue
      }
    }

    if ($f.State -eq 'present') {
      if (!(Test-Path $f.target -PathType Leaf) -or $f.Force) {
        Write-DebugLog "Attempting to create: $($f.target)" -LogLevel Verbose
        if ($f.Source) {
          $f.Source = TemplateStr -InputString $f.Source -PackageName $f._PkgName
          try {
            Copy-Item -Path $f.Source -Destination $f.Target -Force
            Write-DebugLog "Copied file: $($f.Source) -> $($f.target)." -LogLevel INFO
          }
          catch {
            Write-DebugLog "Failed to copy file: $($f.Source) -> $($f.target)." -LogLevel Error
          }
        }
        elseif ($f.Content) {
          try {
            Set-Content -Path $f.Target -Value $f.Content -Force
            Write-DebugLog "Created file from content: $($f.target)." -LogLevel INFO
          }
          catch {
            Write-DebugLog "Failed to create file from content: $($f.target)." -LogLevel Error
          }
        }
      }
    }
  }
}

function Update-Folders {
  param(
    [PsObject[]]$Folders
  )
  
  foreach ($f in $folders) {
    $Path = TemplateStr -InputString $f.Path -PackageName $f._PkgName
    if (!$Path) {
      Write-DebugLog "Path is empty, skipping: $Path" -LogLevel Error
      Continue
    }
    Write-DebugLog "Processing: $Path"
    if ($f.VersionFrom) {
      $VersionFrom = TemplateStr -InputString $f.VersionFrom -PackageName $f._PkgName
      $VersionFile = Split-Path $VersionFrom -Leaf
      if ($VersionFile -eq 'VERSION') {
        $Version = Get-Content $VersionFrom
      }
      else {
        $Version = Get-ExeVersion -Path $VersionFrom
      }
      $result = Set-FolderComment -Path $Path -Comment $Version
      if ($result) {
        Write-DebugLog "Updated folder comment: $Path -> $Version" -LogLevel Info
      }
    }
    
  }
}

function Update-WindowsApps {
  param(
    [PsObject[]]$WindowsApps
  )
  
  $allApps = Get-AppxPackage

  foreach ($a in $WindowsApps) {

    if ($a.state -eq 'absent') {
      if ($a.Name -in $allApps.Name) {
        Write-DebugLog "Attempting to remove: $($a.Name)" -LogLevel Verbose
        try {
          Remove-AppxPackage -Package $a.Name
          Write-DebugLog "Removed app: $($a.Name)." -LogLevel INFO
        }
        catch {
          Write-DebugLog "COMMAND: Remove-AppxPackage -Package $($a.Name)" -logLevel Verbose
          Write-DebugLog -Message $_ -LogLevel Error
        }
      }
      else {
        Write-DebugLog "App already removed: $($a.Name)" -LogLevel Verbose
        continue
      }
    }

  }
}

function Update-WindowsOptionalFeatures {
  param(
    [PsObject[]]$WindowsOptionalFeatures
  )
  
  if (!(IsAdmin)) {
    Write-DebugLog 'Not running as admin, skipping WindowsOptionalFeatures.'
    return
  }
  
  $allFeatures = Get-WindowsOptionalFeature -Online

  foreach ($f in $WindowsOptionalFeatures) {
    $featureState = $allFeatures | Where-Object FeatureName -EQ $f
    if ($f.state -eq 'absent') {
      if ($featureState.State -eq 'Enabled') {
        Write-DebugLog "Attempting to remove: $($f.Name)" -LogLevel Verbose
        try {
          Disable-WindowsOptionalFeature -Online -FeatureName $f.Name -NoRestart | Out-Null
          Write-DebugLog "Removed feature: $($f.Name)." -LogLevel INFO
        }
        catch {
          Write-DebugLog "COMMAND: Disable-WindowsOptionalFeature -Online -FeatureName $($f.Name) -NoRestart" -logLevel Verbose
          Write-DebugLog -Message $_ -LogLevel Error
        }
      }
      else {
        Write-DebugLog "Feature already removed: $($f.Name)" -LogLevel Verbose
        continue
      }
    }
  }
}

function Invoke-LightSync {
  param(
    [string]$PackageFile
  )

  $packages = Get-LightSyncPackageData -PackageFile $PackageFile # Unindexed $packages
  Write-DebugLog -Header 'unfiltered packages data' -Message $($packages | ConvertTo-Yaml) -LogLevel Verbose
  Write-DebugLog "Action is: $Action" -LogLevel Verbose
  if (!([string]::IsNullOrEmpty($Action))) {
    Write-DebugLog "Filtering packages by action: $Action" -LogLevel Verbose
    $packages = $packages.GetEnumerator() | ForEach-Object { if ($action -in $_.keys) { @{$action = $_.$action.Clone(); _PkgName = $_._PkgName; _PkgPath = $_._PkgPath; _Index = $_._Index } } }
    Write-DebugLog -Header 'filtered packages data' -Message $($packages | ConvertTo-Yaml) -LogLevel Verbose
  }

  foreach ($package in $packages) {
    Write-DebugLog "Processing package: $($package._PkgName)"
    $tasks = $package.Keys | Where-Object { $_ -notin @('_PkgName', '_PkgPath', '_Index') }
    Write-DebugLog "Tasks for $($package._PkgName): $tasks"
    foreach ($task in $tasks) {
      Write-DebugLog "Running task ``$task`` for $($package._PkgName)"
      Write-DebugLog -Header 'task data' -Message (Expand-Hashtable $package.$task | ConvertTo-Yaml) -LogLevel Verbose
      switch ($task) {
        'shortcuts' {
          Update-Shortcuts `
            -PackageName $package._PkgName `
            -PackagePath $package._PkgPath `
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
        'assocs' {
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
        'ShellStaticVerbs' {
          Update-ShellStaticVerbs -ShellStaticVerbs $package.ShellStaticVerbs
          # $DEBUG}EPTH - to set externally for the level of logging to display
        }
        'paths' {
          # Expand array paths into dictionaries
          # TODO - This can go in load function 
          $Paths = @();
          foreach ($path in $package.paths) {
            if ( $path -is [string]) {
              $path = @{ 
                Path     = $path; 
                State    = 'present'
                _PkgName = $package._PkgName
                _PkgPath = $package._PkgPath
              }
            }
            $Paths += $path
          }

          Update-Paths -Paths $Paths
        }
        'reg' {
          Update-Regs -Regs $package.reg
        }
        'regswild' {
          Update-Regswild -Regswild $package.regswild
        }
        'fonts' {
          Update-Fonts -Fonts $package.fonts
        }
        'dropboxignore' {
          Update-DropboxIgnore -DropboxIgnore $package.dropboxignore
        }
        'dropboxoffline' {
          Update-DropboxOffline -DropboxOffline $package.dropboxoffline
        }
        'runonce' {
          Update-RunOnce -RunOnce $package.runonce
        }
        'junction' {
          Update-Junctions -Junctions $package.junction
        }
        'symlink' {
          Update-Symlinks -Symlinks $package.symlink
        }
        'files' {
          Update-Files -Files $package.files
        }
        'folders' {
          Update-Folders -Folders $package.folders
        }
        'windowsApps' {
          Update-WindowsApps -WindowsApps $package.windowsApps
        }
        'windowsOptionalFeatures' {
          Update-WindowsOptionalFeatures -WindowsOptionalFeatures $package.windowsOptionalFeatures
        }
      }
    }
  }
}

$STARTUP = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$LSDREG = 'HKEY_CURRENT_USER\SOFTWARE\LightSync'
$LIGHTSYNCROOT = (Get-LighSyncDrivePath).DrivePath
$ISADMIN = IsAdmin
$APP_SHORTCUT_SUFFIX = [char]0x26a1
# $APP_SHORTCUT_SUFFIX = "LSA"
$START_MENU_FOLDER = 'LightSync.sh'
# $DEBUGDEPTH - to set externally for the level of logging to display
# $DEBUGDEPTH = 3
