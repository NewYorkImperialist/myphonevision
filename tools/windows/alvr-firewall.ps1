# Run as Administrator. Windows marks the Pixel's USB tether as a Public
# network, so let ALVR's streaming ports through on every profile.
$ErrorActionPreference = "Stop"
foreach ($proto in "UDP", "TCP") {
  $name = "myphonevision ALVR $proto"
  if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol $proto `
      -LocalPort 9943-9944 -Action Allow -Profile Any | Out-Null
  }
}
# The UDP controller fallback reaches the bridge on 39600.
if (-not (Get-NetFirewallRule -DisplayName "myphonevision bridge UDP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "myphonevision bridge UDP" -Direction Inbound -Protocol UDP `
    -LocalPort 39600 -Action Allow -Profile Any | Out-Null
}
Get-NetFirewallRule -DisplayName "myphonevision*" | Format-Table DisplayName, Enabled, Profile
