### 101:
# Install-Module 'PSDscResources' -Verbose
# Set-WsManQuickConfig -Force
# ?  Remove-DscConfigurationDocument -Stage Pending

Remove-DscConfigurationDocument -Stage Pending

subst n: d:\Dropbox

$person = "KELL NAGZON"

$DBXRoot = "N:\Tools"
$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DBXSync"
$StartUp = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"


Configuration ConEmuPortable {
  param
  (
    [String]$UserName
  )

  Import-DscResource -ModuleName DSCR_Font
  Import-DscResource -ModuleName DSCR_Shortcut

  Node "localhost" {
    File TestFile {
      #ResourceName
      DestinationPath = 'D:\temp\_hello.txt'
      Contents        = "Hello, ${person}!"
      Force           = $true
      Type            = 'File'
      Ensure          = 'Present'
    }

    # Install-Module -Name DSCR_Font; Import-Module -Name DSCR_Font
    # Install-Module -Name DSCR_Shortcut; Import-Module -Name DSCR_Shortcut
    cFont Add_Cascadia {
      Ensure   = 'Present'
      FontName = 'Cascadia Code PL'
      FontFile = "$DBXRoot\ConEmuPortable\_ExtRes\CascadiaCodePL.ttf"
    }

    cShortcut ConEmuPortable {
      Path      = "$StartMenu\ConEmu-DBX.lnk"
      Target    = "$DBXRoot\ConEmuPortable\ConEmuPortable.exe"
      Arguments = ''
      Icon      = "$DBXRoot\ConEmuPortable\App\ConEmu\ConEmu.exe"
    }    
  }
}

ConEmuPortable -OutputPath "./ConEmuPortable"
# winrm quickconfig
Start-DscConfiguration -Wait -Verbose -Path ./ConEmuPortable
