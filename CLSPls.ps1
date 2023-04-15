param(
  [Parameter(Mandatory = $true)][string]$CLSID
)

$CLSID = $CLSID -replace '[{}]', ''
$oi = [System.Activator]::CreateInstance([type]::GetTypeFromCLSID($CLSID))

$oi | gm | out-string | Write-Host

return $oi
