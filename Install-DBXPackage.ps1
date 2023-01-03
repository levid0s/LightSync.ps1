# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force

param(
  [string]$PackageFile = "./packages/sysinternals.yaml"
)

$InformationPreference = 'Continue'
$DebugPreference = 'Continue'
$VerbosePreference = 'Continue'

${Dry-Run} = $false

$DBXRoot = "N:\Tools"

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


$PackageObj = Get-Content $PackageFile | ConvertFrom-Yaml
$PackageName = [System.IO.Path]::GetFileNameWithoutExtension($PackageFile)
$PackageNameDSC = 'DSC-' + $PackageName -replace '[^0-9a-zA-Z-]', ''

Install-ModuleIfNotPresent 'PowerShell-YAML'

Install-ModuleIfNotPresent 'DSCR_Shortcut'
Install-ModuleIfNotPresent 'DSCR_FileAssoc'

if ($PackageObj.Shortcuts.Assoc) {
  
  $CredsNeeded = $true
}
else {
  $CredsNeeded = $false
}

if ($CredsNeeded -and $PsDscRunAsCreds -eq $null) {
  [PSCredential]$PsDscRunAsCreds = Get-Credential
}

#$PsDscRunAsCreds = $env:PsDscRunAsCreds

$Config = @{
  AllNodes = @(
    @{
      NodeName                    = 'localhost'
      PSDscAllowPlainTextPassword = $true
    }
  )
}

$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DBXSync"
$StartUp = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

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

      cShortcut $sobj {
        Path      = "$StartMenu\$(TemplateStr($s.Name)) DBX.lnk"
        Target    = TemplateStr($s.Target)
        Arguments = TemplateStr($s.Args)
        Icon      = TemplateStr($s.Icon)
        Ensure    = "Present"
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
###  Do the paths manually
###

if($PackageObj.Paths) {
  $PathsStr = TemplateStr($PackageObj.Paths -join ';')
  $PathsList = $PathsStr -split ';'
  Add-UserPaths($PathsList)  
}
