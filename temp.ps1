

# $c = Get-LightSyncPackageData -Transpose
# $t = $c[8]
# $n = $t.shortcuts | ? assoc | % { $p = $_; $_.assoc | % { @{ $_ = $p.clone() } } }

# $c = Get-LightSyncPackageData -Transpose
# $c.shortcuts | ? assoc | % { $p = $_; $_.assoc | % { [PSCustomObject]$p } }

# $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $app = $_; $_.assoc | % { "$p -> $($app.Target) -> $($_)" } } }


# $c | % { $p = $_.PkgName; $_.shortcuts | ? assoc | % { $app = $_; $_.assoc | % { $appn = [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($app)); $appn.PkgName = $p; $appn.Assoc = $_ } } }
# [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($data))

# $serialData = 
# $data2 = [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($data))

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
