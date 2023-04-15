function Expand-Hashtable {
  <#
  Experimental function to recursively expands any hastables into a PSCustomObject.
  Not great, because it doesn't show all parameters of the objects, only of the first one.
  #>
  param(
    $InputObject,
    [int]$Level = 0,
    [string]$Parent = 'root'
  )

  if ($InputObject -is [array] -or $InputObject -is [System.Collections.Generic.List`1[System.Object]]) {
    $Output = @()
    foreach ($o in $InputObject) {
      $Output += Expand-Hashtable $o -Level ($Level + 1) -Parent $parent
    }
    return $Output
  }

  if ($InputObject -is [hashtable]) {
    # Write-Debug "[L${Level}: $parent Hashtable] detected: $($InputObject.Keys)"
    $Output = [PSCustomObject]$InputObject
    foreach ($k in $InputObject.keys) {
      $Output.$k = Expand-Hashtable $InputObject[$k] -Level ($Level + 1) -Parent "$parent.$($InputObject.PkgName).$k"
    }
    return $Output
  }
  else {
    return $InputObject
  }
}

function Expand-Basic {
  <#
  Small function to expand an array of hashtables into a PSCustomObject.
  #>
  param(
    $InputObject
  )
  foreach ($o in $InputObject) {
    [PSCustomObject]$o
  }
}

function Convert-Hashtable {
  <#
  Experimental function to recursively implode any hastables into strings. Unfinished.
  #>
  param(
    $InputObject
  )
  if ($InputObject -isnot [hashtable]) {
    return $InputObject
  }
  [string]$output = '@{'
  foreach ($k in $InputObject.keys) {
    $output += "$k= $($InputObject[$k]);"
  }
  $output += '}'
  return $output
}

function Save-Icon {
  param(
    [string]$IconPath
  )

  $iconFilePath, $iconIndex = $IconPath.Split(',')
  if (!(Test-Path $iconFilePath)) {
    Throw "Icon file '$iconFilePath' not found."
  }
  if ($iconIndex) {
    $iconIndex = "_$iconIndex"
  }
  $iconParent = Split-Path $iconFilePath -Parent
  $iconName = Split-Path $iconFilePath -Leaf
  # Remove extension
  $iconName = $iconName -replace '\.[^.]*$', ''
  $iconName = "${iconName}${iconIndex}.ico"
  $newIconPath = "$iconParent\$iconName"
  
  Add-Type -AssemblyName System.Drawing
  $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconFilePath)
  $icon.Save([System.IO.File]::Create($newIconPath))
}

function Refresh-IconCache {
  $shell = New-Object -ComObject 'Shell.Application'
  $startMenu = $shell.NameSpace(0x0A)
  $desktop = $shell.NameSpace(0)
  
  $startMenu.Items() | ForEach-Object { $_.InvokeVerb('refresh') }
  $desktop.Items() | ForEach-Object { $_.InvokeVerb('refresh') }
}
