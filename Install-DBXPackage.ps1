# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force

param(
  [Parameter(Mandatory = $true)][string]$PackageFile
)

$InformationPreference = 'Continue'
$DebugPreference = 'Continue'
$VerbosePreference = 'Continue'

${Dry-Run} = $false

$DropboxRealRoot = "D:\Dropbox"
$DBXRoot = "N:\Tools"
$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DBXSync"
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

$PackageObj = Get-Content $PackageFile | ConvertFrom-Yaml
$PackageName = [System.IO.Path]::GetFileNameWithoutExtension($PackageFile)
$PackageNameDSC = 'DSC-' + $PackageName -replace '[^0-9a-zA-Z-]', ''

Install-ModuleIfNotPresent 'PowerShell-YAML'
Install-ModuleIfNotPresent 'DSCR_Shortcut'
Install-ModuleIfNotPresent 'DSCR_FileAssoc'


$AdminNeeded = $PackageObj.Shortcuts -ne $null

if ($AdminNeeded) {
  If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    # TBC
    # $ScriptPath = $MyInvocation.MyCommand.Definition
    # $PsCmd = (Get-ChildItem -Path "$PSHome\pwsh*.exe", "$PSHome\powershell*.exe")[0]
    # Start-Process "$PsCmd" `
    #   -Verb runAs `
    #   -ArgumentList "-File", "$ScriptPath", '-$PackageFile', "$PackageFile"
    # Break
  }
}

$CredsNeeded = $PackageObj.Shortcuts.Assoc -ne $null

if ($CredsNeeded -and $PsDscRunAsCreds -eq $null) {
  Throw 'Please run:    [PSCredential]$PsDscRunAsCreds = Get-Credential   '
}

$Config = @{
  AllNodes = @(
    @{
      NodeName                    = 'localhost'
      PSDscAllowPlainTextPassword = $true
    }
  )
}


Configuration $PackageNameDSC {
  Import-DscResource -ModuleName DSCR_Shortcut
  Import-DscResource -ModuleName DSCR_Font
  Import-DscResource -ModuleName DSCR_FileAssoc
  # Import-DscResource -ModuleName xPSDesiredStateConfiguration

  Node localhost {

    $i = 0
    foreach ($s in $PackageObj.Shortcuts) {
      $i ++
      $sobj = [System.IO.Path]::GetFileNameWithoutExtension($s.Target)
      # StartIn in exe's folder by default.
      
      $Target = TemplateStr($s.Target)

      if ($s.StartIn -eq $null) { 
        $StartIn = Split-Path -Path $Target 
      }
      else { 
        $StartIn = TemplateStr($s.StartIn) 
      }

      cShortcut $sobj {
        Path             = "$StartMenu\$(TemplateStr($s.Name)) DBX.lnk"
        Target           = $Target
        Arguments        = TemplateStr($s.Args)
        Icon             = TemplateStr($s.Icon)
        WorkingDirectory = $StartIn
        Ensure           = "Present"
      }

      foreach ($ext in $s.Assoc) {
        $aobj = "Assoc-$i-$ext"
        $assocCmd = $s.Target + $s.AssocParam
        cFileAssoc $aobj {
          Extension            = $ext
          FileType             = "LibreOfficeDBX." + $ext
          Command              = $assocCmd
          PsDscRunAsCredential = ($PsDscRunAsCreds)
          Ensure               = "Present"
        }        
      }
    }

    foreach ($f in $PackageObj.Fonts) {
      $fobj = $f.name
      cFont $fobj {
        FontName = TemplateStr($f.name)
        FontFile = TemplateStr($f.path)
        Ensure   = 'Present'
      }    
    }

    $i = 0
    # foreach ($r in $PackageObj.reg) {
    #   $robj ++
    #   Registry $robj {
    #     Key       = $r.key
    #     ValueName = $r.valuename
    #     ValueData = TemplateStr($r.valuedata)
    #     ValueType = $r.valuetype
    #     Force     = $true
    #     PsDscRunAsCredential = ($PsDscRunAsCreds)
    #     Ensure    = "Present"  # You can also set Ensure to "Absent"
    #   }      
    # }

    # $pObj = 1
    # foreach ($p in $PackageObj.Paths) {
    #   xEnvironment $pObj {
    #     Name                 = 'Path'
    #     Value                = TemplateStr($p)
    #     Path                 = $true
    #     Ensure               = 'Present'
    #     PsDscRunAsCredential = ($PsDscRunAsCreds)
    #     Target               = 'Process'
    #   }      
    # }

  }
}

###
###  Run the DSC
###

Remove-DscConfigurationDocument -Stage Pending
Invoke-Expression "$PackageNameDSC -ConfigurationData `$Config -OutputPath `"./mofs/$PackageNameDSC`" "
Start-DscConfiguration -Wait -Verbose -Path "./mofs/$PackageNameDSC"

###
###  Set Folder comment
###

foreach ($f in $PackageObj.Folders) {
  
  if ($f.VersionFrom) {
    $Version = Get-ExeVersion(TemplateStr($f.VersionFrom))
    Set-FolderComment -Path (TemplateStr($f.Path)) -Comment $Version
  }
}

###
###  Do the paths manually
###

if ($PackageObj.Paths) {
  $PathsStr = TemplateStr($PackageObj.Paths -join ';')
  $PathsList = $PathsStr -split ';'
  Add-UserPaths($PathsList)  
}

###
###  Do regs manually
###

foreach ($r in $PackageObj.reg) {
  $r.key = $r.key -replace 'HKEY_CURRENT_USER\\', 'HKCU:\' -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:\'
  if (!$r.name) { $r.Name = '(Default)' }
  if (!$r.type) { $r.Type = 'String' }
  New-ItemProperty -Path $r.key -Name $r.name -Value (TemplateStr($r.data))  -PropertyType $r.type -Verbose -Force
}
