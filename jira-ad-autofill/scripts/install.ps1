param(
  [Parameter(Mandatory=$true)] [string]$ExtensionId
)
$ErrorActionPreference = 'Stop'
$hostName = 'com.company.adwhoami'
$hostExe  = Join-Path $env:LOCALAPPDATA 'JiraAdAutofill\host\AdWhoAmI.exe'
$manifestPath = Join-Path $env:LOCALAPPDATA 'JiraAdAutofill\com.company.adwhoami.json'

if (-not (Test-Path $hostExe)) { throw "Host exe not found: $hostExe - run scripts\build.ps1 first" }

$manifest = @{
  name = $hostName
  description = 'Return AD username (sAMAccountName) to extension'
  path = $hostExe
  type = 'stdio'
  allowed_origins = @("chrome-extension://$ExtensionId/")
} | ConvertTo-Json -Depth 5

$null = New-Item -ItemType Directory -Force -Path (Split-Path $manifestPath)
$manifest | Out-File -Encoding UTF8 -FilePath $manifestPath

reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\$hostName" /ve /t REG_SZ /d "$manifestPath" /f | Out-Null
reg add "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\$hostName" /ve /t REG_SZ /d "$manifestPath" /f | Out-Null

Write-Host "Installed host manifest: $manifestPath"
Write-Host "Registered for Chrome and Edge (HKCU)"
