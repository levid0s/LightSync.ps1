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
  Import-DscResource -ModuleName DSCR_Shortcut

  Node "localhost" {
    # Install-Module -Name DSCR_Shortcut; Import-Module -Name DSCR_Shortcut

    cShortcut Shortcut {
      Path      = "$StartMenu\7-zip DBX.lnk"
      Target    = "$DBXRoot\7-zip\7zFM.exe"
    }    
  }
}

Invoke-Expression "$ModuleName -OutputPath `"./mofs/$ModuleName`" "
Start-DscConfiguration -Wait -Verbose -Path "./mofs/$ModuleName"
