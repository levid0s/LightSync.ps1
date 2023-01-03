### 101:
# Install-Module 'PSDscResources' -Verbose
# Set-WsManQuickConfig -Force
# ?  Remove-DscConfigurationDocument -Stage Pending

Remove-DscConfigurationDocument -Stage Pending

subst n: d:\Dropbox

$DBXRoot = "N:\Tools"
$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DBXSync"
$StartUp = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

$version = "7.4.2"

$Config = @{
  AllNodes = @(
    @{
      NodeName                    = 'localhost'
      PSDscAllowPlainTextPassword = $true
    }
  )
}

$Shortcuts = @(
  @{
    Name       = "$StartMenu\LibreOffice Writer $version DBX.lnk"
    Target     = "$DBXRoot\LibreOfficePortable-$version\LibreOfficeWriterPortable.exe"
    Assoc      = @('txn', 'doc', 'docx')
    AssocParam = ' -o "%1"'
  },
  @{
    Name   = "$StartMenu\LibreOffice Calc $version DBX.lnk"
    Target = "$DBXRoot\LibreOfficePortable-$version\LibreOfficeCalcPortable.exe"
    Assoc  = @('xls', 'xlsx')
    AssocParam = ' -o "%1"'
    
  },
  @{
    Name   = "$StartMenu\LibreOffice Draw $version DBX.lnk"
    Target = "$DBXRoot\LibreOfficePortable-$version\LibreOfficeDrawPortable.exe"
  },
  @{
    Name   = "$StartMenu\LibreOffice $version DBX.lnk"
    Target = "$DBXRoot\LibreOfficePortable-$version\LibreOfficePortable.exe"
  }
)

Configuration LibreOfficePortable {
  Import-DscResource -ModuleName PSDesiredStateConfiguration
  Import-DscResource -ModuleName DSCR_Shortcut
  Import-DscResource -ModuleName DSCR_FileAssoc

  Node localhost {

    # Install-Module -Name DSCR_Font; Import-Module -Name DSCR_Font
    # Install-Module -Name DSCR_Shortcut; Import-Module -Name DSCR_Shortcut
    # Install-Module -Name DSCR_FileAssoc

    $i = 0
    foreach ($s in $Shortcuts) {
      $i ++
      $sobj = "$s$i"

      cShortcut $sobj {
        Ensure = "Present"
        Path   = $s.Name
        Target = $s.Target
        # Arguments = ''
        # Icon      = "$DBXRoot\ConEmuPortable\App\ConEmu\ConEmu.exe"
      }

      foreach ($ext in $s.Assoc) {
        $aobj = "Assoc-$i-$ext"
        $assocCmd = $s.Target + $s.AssocParam
        cFileAssoc $aobj {
          Ensure               = "Present"
          Extension            = $ext
          FileType = "LibreOfficeDBX." + $ext
          Command              = $assocCmd
          PsDscRunAsCredential = ($PsDscRunAsCreds)
        }
        
        # Registry $aobj {
        #   Ensure    = "Present"  # You can also set Ensure to "Absent"
        #   # Key       = "HKEY_CURRENT_USER\SOFTWARE\Classes\." + $a
        #   Key       = "HKEY_CURRENT_USER\_1." + $a
        #   ValueName = "(Default)"
        #   ValueData = "LibreOfficeDBX." + $a
        #   ValueType = 'String'
        # }        
      }
    }
  }
}

if($Shortcuts.Assoc) {
  $CredsNeeded = $true
}

if($CredsNeeded -and !$PsDscRunAsCreds) {
  [PSCredential]$PsDscRunAsCreds = Get-Credential
}


LibreOfficePortable -ConfigurationData $Config  -OutputPath "./mofs/LibreOfficePortable"
# winrm quickconfig
Start-DscConfiguration -Wait -Verbose -Path ./mofs/LibreOfficePortable
