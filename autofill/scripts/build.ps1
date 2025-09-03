$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$hostDir = Join-Path $env:LOCALAPPDATA 'JiraAdAutofill\host'
New-Item -ItemType Directory -Force -Path $hostDir | Out-Null

Push-Location (Join-Path $root 'native-host')
try {
  dotnet restore
  dotnet publish -c Release --self-contained true
  $exe = Get-ChildItem -Recurse .\bin\Release | Where-Object { $_.Extension -eq '.exe' -and $_.DirectoryName -match 'publish' } | Select-Object -First 1
  if (-not $exe) { throw 'ไม่พบไฟล์ exe ที่ publish' }
  Copy-Item $exe.FullName -Destination (Join-Path $hostDir 'AdWhoAmI.exe') -Force
  Write-Host "Build OK -> $hostDir\AdWhoAmI.exe"
} finally {
  Pop-Location
}
