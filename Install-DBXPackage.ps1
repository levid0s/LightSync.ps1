param(
  [string]$PackageFile = "./packages/7-zip.yaml"
)

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

  return $NewString
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

  Node localhost {

    $i = 0
    foreach ($s in $PackageObj.Shortcuts) {
      $i ++
      $sobj = [System.IO.Path]::GetFileNameWithoutExtension($s.Target)

      cShortcut $sobj {
        Ensure    = "Present"
        Path      = "$StartMenu\$(TemplateStr($s.Name)) DBX.lnk"
        Target    = TemplateStr($s.Target)
        Arguments = TemplateStr($s.Args)
        Icon      = TemplateStr($s.Icon)
      }

      foreach ($ext in $s.Assoc) {
        $aobj = "Assoc-$i-$ext"
        $assocCmd = $s.Target + $s.AssocParam
        cFileAssoc $aobj {
          Ensure               = "Present"
          Extension            = $ext
          FileType             = "LibreOfficeDBX." + $ext
          Command              = $assocCmd
          PsDscRunAsCredential = ($PsDscRunAsCreds)
        }        
      }
    }
  }
}

###
###  Run the DSC
###

Remove-DscConfigurationDocument -Stage Pending
Invoke-Expression "$PackageNameDSC -ConfigurationData `$Config -OutputPath `"./mofs/$PackageNameDSC`" "
Start-DscConfiguration -Wait -Verbose -Path "./mofs/$PackageNameDSC"
