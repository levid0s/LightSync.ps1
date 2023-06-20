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

function Expand-ObjectUi {
  <#
  .VERSION 2023.04.22

  .SYNOPSIS
  Recursively expands any object into a TreeView Form.

  .EXAMPLE
  Expand-ObjectUi -InputObject $packages -FindNameFields 'target','path','Name','PkgName'

  #>
  param(
    [Parameter(Mandatory = $true)]$InputObject,
    [Parameter(Mandatory = $false)]$ParentNode,
    [Parameter(Mandatory = $false)][string[]]$FindNameFields # List of fields from where the Hashtable label can be extracted from
  )

  $enumTypes = @{list = @('Object[]', 'List`1'); map = @('Hashtable') }

  if (!$ParentNode) {
    Write-Host 'Creating the form.'
    # Load the required assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create the main form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Hashtable Viewer'
    $form.Size = New-Object System.Drawing.Size(800, 600)

    # Create the TreeView control
    $treeView = New-Object System.Windows.Forms.TreeView
    $treeView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($treeView)

    $ParentNode = $treeView
  }

  if ($InputObject.GetType().Name -in ($enumTypes['map'] -split ' ')) {
    foreach ($key in ($InputObject.Keys | Sort-Object)) {
      $node = New-Object System.Windows.Forms.TreeNode
      $node.Name = $key
      if ($null -eq $InputObject[$key]) {
        $node.Text = $key
        $parentNode.Nodes.Add($node) | Out-Null
      }
      elseif ($InputObject[$key].GetType().Name -in ($enumTypes.Values -split ' ')) {
        $node.Text = $key
        $parentNode.Nodes.Add($node) | Out-Null
        Expand-ObjectUi -InputObject $InputObject[$key] -ParentNode $node -FindNameFields $FindNameFields
      }
      else {
        $node.Text = "${key}: $($InputObject[$key])"
        $parentNode.Nodes.Add($node) | Out-Null
      }
    }
  }
  elseif ($InputObject.GetType().Name -in ($enumTypes['list'] -split ' ')) {
    Write-Debug 'Enumerating list..'
    $index = -1
    foreach ($item in $InputObject) {
      $index++
      $node = New-Object System.Windows.Forms.TreeNode

      if ($item.GetType().Name -in ($enumTypes.Values -split ' ')) {
        $findName = $null
        foreach ($field in $FindNameFields) {
          if ($item.ContainsKey($field)) {
            $findName = ($item.GetType().Name) + ': ' + $item[$field]
            break
          }
        }
        if (!$findName) {
          $findName = ($item.GetType().Name) + ': ' + $index
        }
      }
      else {
        $findName = $item.Name
      }
      $node.Text = $findName
      $node.Name = $item.GetType().Name
      $parentNode.Nodes.Add($node) | Out-Null

      Expand-ObjectUi -InputObject $item -ParentNode $node -FindNameFields $FindNameFields
    }
  }
  elseif (($InputObject | Get-Member -MemberType Property).Count -gt 1) {
    $members = Get-Member -InputObject $InputObject -MemberType Property
    foreach ($m in $members) {
      $node = New-Object System.Windows.Forms.TreeNode
      $node.Name = $m.Name
      $node.Text = "$($m.Name): $($InputObject.$($m.Name))"
      $parentNode.Nodes.Add($node) | Out-Null
      # Expand-ObjectUi -InputObject $item.$($m.Name) -ParentNode $node -FindNameFields $FindNameFields
    }
  }  
  else {
    $node = New-Object System.Windows.Forms.TreeNode
    $node.Text = $InputObject.ToString()
    $node.Name = $InputObject
    $parentNode.Nodes.Add($node) | Out-Null
  }

  if (!$ParentNode -or $ParentNode.GetType().Name -eq 'TreeView') {
    Write-Host 'Displaying form..'

    # Event handler for KeyDown event
    $treeView.Add_KeyDown({
        if ($_.KeyCode -ge [System.Windows.Forms.Keys]::D0 -and $_.KeyCode -le [System.Windows.Forms.Keys]::D9) {
          $level = $_.KeyCode - [System.Windows.Forms.Keys]::D0 - 2

          function UpdateTreeNodes ($nodes, $currentLevel) {
            foreach ($node in $nodes) {
              if ($currentLevel -le $level) {
                $node.Expand()
              }
              else {
                $node.Collapse()
              }

              if ($node.Nodes.Count -gt 0) {
                UpdateTreeNodes $node.Nodes ($currentLevel + 1)
              }
            }
          }

          UpdateTreeNodes $treeView.Nodes 0
          if ($null -ne $treeView.SelectedNode) {
            $treeView.SelectedNode.EnsureVisible()
          }      
        }
      })

    # Set focus to the TreeView control
    $treeView.Focus()

    [System.Windows.Forms.Application]::Run($form)

  }
}
