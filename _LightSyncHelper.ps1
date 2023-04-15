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

    $Params = $task.Params

    $WindowStyle = switch ($task.WindowStyle) {
      $null { 'Default' }
      default { $_ }
    }

    $Unrecognized = $task.keys | Where-Object { $_ -notin @('name', 'target', 'startin', 'params', 'icon', 'assoc', 'assocIcon', 'assocparam', 'tindex', 'PkgPath', 'PkgName') }
    if ($Unrecognized) {
      Write-Warning "Unrecognized keys in task $($task.Name): $Unrecognized"
    }

    Write-DebugLog "LinkPath: $LinkPath, Target: $Target, Params: $Params, StartIn: $StartIn, IconPath: $IconPath, WindowStyle: $WindowStyle"
    New-Shortcut `
      -LnkPath $LinkPath `
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
        $Action.Add('PkgName', $PackageName)
        $Action.Add('PkgPath' , "${LIGHTSYNCROOT}\$PackageName" )
        $Action.Add('tindex' , $tindex)
        $tindex++

      }
    }
    $PackageObj.Add('PkgName', $PackageName)
    $PackageObj.Add('PkgPath' , "${LIGHTSYNCROOT}\$PackageName" )
    $PackageObj.Add('Index', $Index)

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

    $RemainingKeys = (Compare-Object -ReferenceObject $Keys -DifferenceObject $OrderedKeysList | Where-Object SideIndicator -EQ '<=' | Select-Object -ExpandProperty InputObject)
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

  PkgName                   assoc target                                   assocParam assocIcon           description  force  verb     verblabel
  -------                   ----- ------                                   ---------- ---------           -----------  -----  -------  -----
  7-zip                     zip   {PkgPath}/7zFM.exe                                  {PkgPath}/7z.dll,1  Zip archive  true   enqueue  Enqueue in Winamp
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
      -AppRegSuffix 'LSH' `
      -Verb $a.Verb `
      -VerbLabel $a.VerbLabel `
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
      # continue
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

function Set-ShellStaticVerb {
  # OS level function
  param(
    [Parameter(Mandatory = $true)][string]$Class,
    [Parameter(Mandatory = $true)][string]$Verb,
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$Label
  )

  $key = "HKCU:\SOFTWARE\Classes\${Class}\shell\${Verb}\(Default)"
  Set-RegValue -FullPath $key -Value $Label -Type String -Force

  $key = "HKCU:\SOFTWARE\Classes\${Class}\shell\${Verb}\command\(Default)"
  Set-RegValue -FullPath $key -Value $Target -Type String -Force
}

function Update-ShellStaticVerbs {
  param(
    [PsObject]$ShellStaticVerbs
  )

  foreach ($v in $ShellStaticVerbs) {
    $target = TemplateStr -InputString $v.Target -PackageName $v.PkgName
    Set-ShellStaticVerb -class $v.class -Verb $v.Verb -Target $target -Label $v.verblabel
  }
}

function Update-DropboxIgnore {
  param(
    [PsObject]$DropboxIgnore
  )

  foreach ($d in $DropboxIgnore) {
    $target = TemplateStr -InputString $d.target -PackageName $d.PkgName
    Write-DebugLog "Updating Dropbox ignore file: $target"
    Set-DropboxIgnoredPath -Path $target
  }
}

function Update-DropboxOffline {
  param(
    [PsObject]$DropboxOffline
  )

  foreach ($d in $DropboxOffline) {
    $target = TemplateStr -InputString $d.Path -PackageName $d.PkgName
    Write-DebugLog "Updating Dropbox offline file: $target, mode: $($d.Mode)"
    Set-DropboxItemOfflineMode -Path $target -Mode $d.Mode -ErrorAction SilentlyContinue
  }
}

function Update-RunOnce {
  param(
    [PsObject]$RunOnce,
    [switch]$Force
  )

  foreach ($r in $RunOnce) {
    $command = TemplateStr -InputString $r.command -PackageName $r.PkgName
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
      Write-Warning "RunOnce command failed: $command"
      return
    }

    Set-RegValue -FullPath "$LSDREG\RunOnceData\$hash" -Value $command -Type String -Force
  }
}

function Update-Junctions {
  param(
    [PsObject]$Junctions
  )

  foreach ($j in $Junctions) {
    # Target is the real path
    $target = TemplateStr -InputString $j.target -PackageName $j.PkgName
    $target = $ExecutionContext.InvokeCommand.ExpandString($target)
    if (!(Test-Path $target)) {
      Write-DebugLog "Target doesn't exist: $target. Skipping."
      Continue
    }
    $target = Get-RealPath $target

    # Junction is the virtual path
    $junction = TemplateStr -InputString $j.link -PackageName $j.PkgName
    $junction = $ExecutionContext.InvokeCommand.ExpandString($junction)
    $junctionParent = Split-Path $junction -Parent
    if (!(Test-Path $junctionParent)) {
      Write-DebugLog "Junction parent doesn't exist: $junctionParent. Skipping."
      continue
    }
    $junctionLeaf = Split-Path $junction -Leaf
    $junctionParent = Get-RealPath $junctionParent
    $junction = "$junctionParent\$junctionLeaf"
    if (Test-Path $junction) {
      if ($j.Force) {
        $junctionBackup = "$junction-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-DebugLog "Something already exists at the junction's path, moving it out of the way: $junction -> $junctionBackup"
        Rename-Item -Path $junction -NewName $junctionBackup
      }
      else {
        Write-DebugLog "Something already exists at the junction's path, skipping: $junction"
        Continue
      }
    }

    Write-DebugLog "Creating junction: $junction <- $target"
    New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
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
      Write-DebugLog "Running task ``$task`` for $($package.PkgName) : $(Expand-Hashtable $package.$task)"
      switch ($task) {
        'shortcuts' {
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
        'reg' {
          $Regs = $package.reg
          Update-Regs -Regs $Regs
        }
        'fonts' {
          $Fonts = $package.fonts
          Update-Fonts -Fonts $Fonts
        }
        'dropboxignore' {
          $DropboxIgnore = $package.dropboxignore
          Update-DropboxIgnore -DropboxIgnore $DropboxIgnore
        }
        'dropboxoffline' {
          $DropboxOffline = $package.dropboxoffline
          Update-DropboxOffline -DropboxOffline $DropboxOffline
        }
        'runonce' {
          $RunOnce = $package.runonce
          Update-RunOnce -RunOnce $RunOnce
        }
        'junction' {
          $Junctions = $package.junction
          Update-Junctions -Junctions $Junctions
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