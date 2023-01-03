### 101:

$ModuleName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)


$Shortcuts = @(
  @{
    Name       = "$StartMenu\$ModuleName DBX.lnk"
    Target     = "$DBXRoot\$ModuleName\$ModuleName.exe"
    Assoc      = @('pdf')
    AssocParam = '"%1"'
  }
)






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

    $i = 0
    foreach ($s in $Shortcuts) {
      $i ++
      $sobj = [System.IO.Path]::GetFileNameWithoutExtension($s.Target) + '-' + $i

      cShortcut $sobj {
        Path      = $s.Name
        Target    = $s.Target
        Arguments = $s.Args
        Icon      = $s.Icon
      }    

      foreach ($ext in $s.Assoc) {
        $aobj = $sobj + '-' + $ext
        $assocCmd = $s.Target + ' ' + $s.AssocParam

        cFileAssoc $aobj {
          Ensure               = "Present"
          Extension            = $ext
          FileType = $ModuleName + 'DBX.' + $ext
          Command              = $assocCmd
          PsDscRunAsCredential = ($PsDscRunAsCreds)
        }
    }
  }
}

Invoke-Expression "$ModuleName -OutputPath `"./mofs/DSC-$ModuleName`" "
Start-DscConfiguration -Wait -Verbose -Path "./mofs/DSC-$ModuleName"
