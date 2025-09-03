$ErrorActionPreference = 'SilentlyContinue'
$hostName = 'com.company.adwhoami'
$manifestPath = Join-Path $env:LOCALAPPDATA 'JiraAdAutofill\com.company.adwhoami.json'
$hostDir = Join-Path $env:LOCALAPPDATA 'JiraAdAutofill'

reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\$hostName" /f | Out-Null
reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\$hostName" /f | Out-Null
Remove-Item $manifestPath -Force
Remove-Item $hostDir -Recurse -Force
Write-Host 'Uninstalled native host (user-scope)'
