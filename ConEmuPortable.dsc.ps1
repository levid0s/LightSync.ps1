### 101:
# Install-Module 'PSDscResources' -Verbose
# Set-WsManQuickConfig -Force
# ?  Remove-DscConfigurationDocument -Stage Pending

$ModuleName = "DSC-" + [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

if(!(Test-Path 'N:')) {
  subst n: d:\Dropbox
}

Remove-DscConfigurationDocument -Stage Pending

$DBXRoot = "N:\Tools"
$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DBXSync"
$StartUp = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"


Configuration $ModuleName {
  Import-DscResource -ModuleName DSCR_Font
  Import-DscResource -ModuleName DSCR_Shortcut

  Node "localhost" {
    # File TestFile {
    #   #ResourceName
    #   DestinationPath = 'D:\temp\_hello.txt'
    #   Contents        = "Hello, ${person}!"
    #   Force           = $true
    #   Type            = 'File'
    #   Ensure          = 'Present'
    # }

    # Install-Module -Name DSCR_Font; Import-Module -Name DSCR_Font
    cFont Add_Cascadia {
      Ensure   = 'Present'
      FontName = 'Cascadia Code PL'
      FontFile = "$DBXRoot\ConEmuPortable\_ExtRes\CascadiaCodePL.ttf"
    }

    # Install-Module -Name DSCR_Shortcut; Import-Module -Name DSCR_Shortcut
    cShortcut ConEmuPortable {
      Path      = "$StartMenu\ConEmu-DBX.lnk"
      Target    = "$DBXRoot\ConEmuPortable\ConEmuPortable.exe"
      Arguments = ''
      Icon      = "$DBXRoot\ConEmuPortable\App\ConEmu\ConEmu.exe"
    }    
  }
}

Invoke-Expression "$ModuleName -OutputPath `"./mofs/$ModuleName`" "
Start-DscConfiguration -Wait -Verbose -Path "./mofs/$ModuleName"
