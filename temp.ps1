$APP_SHORTCUT_SUFFIX = [char]0x26a1

# $c="`{0xU+26A1}`"


new-item -itemtype file -name "$APP_SHORTCUT_SUFFIX lev $c.txt"

# $c = Get-LightSyncPackageData -Transpose
# $t = $c[8]
#   }
# }

# foreach ($p in $c.GetEnumerator()) {
#   foreach ($t in $p.GetEnumerator()) {
#     $t | ? $_.value.GetType() -eq 'System.Collections.Generic.List[System.Object]' 
#   }
# }

# foreach ($p in $c.GetEnumerator()) {
#   foreach ($t in $p.GetEnumerator()) {
#     $t | % { $_.GetEnumerator() | ? $_.value.GetType() -eq 'System.Collections.Generic.List[System.Object]' | % { "$($_.name) -> $($_.value.GetType())" } }
#   }
# }
   
# $c = Get-LightSyncPackageData
# $c.GetEnumerator() | % { $_.GetEnumerator() | % { "$($_.Name) -> $($_.Value.GetType()) -> $($_.Value.GetType().IsValueType)"; $_.Value | Where-Object $_ -isnot [hashtable] | % { "->>>> $_ ->>>> $($_.GetType()) ->>> $($_.GetType().TypeData) " } } } 


# $c.GetEnumerator() | % { $_.GetEnumerator() | % { $_ | Get-Member; write-host '>>>>>>>>>>>>>' } }


# $new = @(); $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $p += @{'masso, @() }; $app = $_; $_.assoc | % { $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app)) ; $temp.assoc = $_; $new += $temp } } }
# $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $app = $_; $_.assoc | % { $new = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app)) } } }

# $new = @(); $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $app = $_; $_.assoc | % { $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app)) ; $temp.assoc = $_; $new += $temp } } }



# $_ | foreach { $_ } 


# foreach ($p in $c) {
#   foreach ($t in $p) {
#     $t.
#   }
# }

# foreach ($p in $c.GetEnumerator()) {
#   foreach ($t in $p.GetEnumerator()) {
#     $t | ? $_.value.GetType() -eq 'System.Collections.Generic.List[System.Object]' 
#   }
# }

# foreach ($p in $c.GetEnumerator()) {
#   foreach ($t in $p.GetEnumerator()) {
#     $t | % { $_.GetEnumerator() | ? $_.value.GetType() -eq 'System.Collections.Generic.List[System.Object]' | % { "$($_.name) -> $($_.value.GetType())" } }
#   }
# }
   
# $c = Get-LightSyncPackageData
# $c.GetEnumerator() | % { $_.GetEnumerator() | % { "$($_.Name) -> $($_.Value.GetType()) -> $($_.Value.GetType().IsValueType)"; $_.Value | Where-Object $_ -isnot [hashtable] | % { "->>>> $_ ->>>> $($_.GetType()) ->>> $($_.GetType().TypeData) " } } } 


# $c.GetEnumerator() | % { $_.GetEnumerator() | % { $_ | Get-Member; write-host '>>>>>>>>>>>>>' } }


# $new = @(); $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $p += @{'masso, @() }; $app = $_; $_.assoc | % { $temp = [PsCustomObject][System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app)) ; $temp.assoc = $_; $new += $temp } } }