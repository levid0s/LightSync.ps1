# Install-Module PowerShellGet -Force
# Update-Module PowerShellGet -Force
# winrm quickconfig / maybe??
# + Set Wifi network to Private

param(
  [switch]$Install,
  [string]$PackageFile,
  # TODO - To implement $Action filter
  [Parameter()][ValidateSet('exec', 'files', 'folders', 'fonts', 'paths', 'reg', 'shortcuts', 'symlink')][string]$Action,
  $DebugPreference = 'Continue',
  $ConfirmPreference = 'None'
)

. $PSScriptRoot/LightSyncHelper.ps1

if ($Install) {
  Install-Dependencies
  Install-LightSync
  Install-LightSyncDrive
}

# Create the Global LIGHTSYNCROOT variable

Invoke-LightSync -PackageFile $PackageFile


return

###
###  Program Start
###


$PackageObj = Get-Content $PackageFile | ConvertFrom-Yaml
$PackageName = [System.IO.Path]::GetFileNameWithoutExtension($PackageFile)

###
###  Create Shortcuts
###

foreach ($s in $PackageObj.Shortcuts) {

  $ht = UnderscroreTo-HashTable -InputList $s -Include @('Name', 'Parent', 'Target', 'WindowStyle', 'Icon', 'Args', 'StartIn')

  New-DBXShortcut @ht

}

###
###  Install Font - TBC
###

foreach ($f in $PackageObj.Fonts) {
  Install-Font -SourcePath TemplateStr($f.path)
}

###
###  Set Folder Comments
###

foreach ($f in $PackageObj.Folders) {
  
  if ($f.VersionFrom) {
    $Version = Get-ExeVersion(TemplateStr($f.VersionFrom))
    Set-FolderComment -Path (TemplateStr($f.Path)) -Comment $Version
  }
}

###
###  ADD PATHs
###

if ($PackageObj.Paths) {
  $PathsStr = TemplateStr($PackageObj.Paths -join ';')
  $PathsList = $PathsStr -split ';'
  Add-UserPaths($PathsList)  
}

###
###  Create Registry Entries
###

Write-Debug "REG TIME"

foreach ($r in $PackageObj.reg) {
  write-Debug "Reg: $($r.key)"
  $r.key = $r.key -replace 'HKEY_CURRENT_USER\\', 'HKCU:\' -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM:\'
  if (!$r.name) { $r.Name = '(Default)' }
  if (!$r.type) { $r.Type = 'String' }
	
  if (!(Test-Path $r.key)) {
    New-Item -Path $r.key -Force
  }
  New-ItemProperty -LiteralPath $r.key -Name $r.name -Value (TemplateStr($r.data)) -PropertyType $r.type -Verbose -Force
}


###
###  Do assocs manually
###

foreach ($s in $PackageObj.Shortcuts) {
  if ($s.Assoc) {
    $ExeName = Split-Path (TemplateStr($s.Target)) -Leaf
    $AppRegKey = "HKCU:\\SOFTWARE\\Classes\\Applications\\${ExeName}\\shell\\open\\command"
    if ($s.AssocParam -eq $null) { $s.AssocParam = "`"%1`"" }
    $OpenCmd = "$(TemplateStr($s.Target)) $($s.AssocParam)"
    if (!(Test-Path $AppRegKey)) {
      New-Item -Path $AppRegKey -Force
    }
    New-ItemProperty -LiteralPath $AppRegKey -Name "(Default)" -Value $OpenCmd -PropertyType "ExpandString" -Verbose -Force
  }

  if ($s.AssocIcon) {
    $AppRegKey = "HKCU:\\SOFTWARE\\Classes\\Applications\\${ExeName}\\DefaultIcon"
    $IconPath = TemplateStr($s.AssocIcon)

    if (!(Test-Path $AppRegKey)) {
      New-Item -Path $AppRegKey -Force
    }
    New-ItemProperty -LiteralPath $AppRegKey -Name "(Default)" -Value $IconPath -PropertyType "ExpandString" -Verbose -Force    
  }

  foreach ($ext in $s.Assoc) {
    $ExtRegKey = "HKCU:\\SOFTWARE\\Classes\\.${ext}\\OpenWithList\\${ExeName}"
    if (!(Test-Path $ExtRegKey)) {
      New-Item -Path $ExtRegKey -Force
    }
  }
}


###
###  Run the DSC
###

# $CredsNeeded = $PackageObj.Shortcuts.Assoc -ne $null

# if ($CredsNeeded -and $PsDscRunAsCreds -eq $null) {
#   Throw 'Please run:    [PSCredential]$PsDscRunAsCreds = Get-Credential   '
# }

# Remove-DscConfigurationDocument -Stage Pending
# Invoke-Expression "$PackageNameDSC -ConfigurationData `$Config -OutputPath `"./mofs/$PackageNameDSC`" "
# Start-DscConfiguration -Wait -Verbose -Path "./mofs/$PackageNameDSC"
