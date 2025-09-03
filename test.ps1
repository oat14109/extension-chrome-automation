# --- collect basics ---
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem

$payload = [ordered]@{
  hostname     = $env:COMPUTERNAME
  domain       = $env:USERDOMAIN
  username     = $env:USERNAME
  serial       = $bios.SerialNumber
  manufacturer = $cs.Manufacturer
  model        = $cs.Model
  os           = "$($os.Caption) $($os.Version) ($($os.OSArchitecture))"
  lastBoot     = $os.LastBootUpTime
}

# --- enrich from AD (optional) ---
try {
  Import-Module ActiveDirectory -ErrorAction Stop
  $adUser = Get-ADUser -Identity $env:USERNAME -Properties mail,department,title,telephoneNumber
  if ($adUser) {
    $payload.userEmail  = $adUser.mail
    $payload.department = $adUser.department
    $payload.title      = $adUser.title
    $payload.phone      = $adUser.telephoneNumber
  }
  $adComp = Get-ADComputer -Identity $env:COMPUTERNAME -Properties DistinguishedName
  if ($adComp) {
    $payload.computerOU = $adComp.DistinguishedName
  }
} catch { }

# --- security secret (match Automation condition) ---
$payload.secret = "21a6960cabfbfc3b96098b8ec1c5d9b81de6f6a8"   # <<< ตั้งให้ตรงกับใน Automation

# --- post to Jira webhook ---
$webhookUrl = "https://api-private.atlassian.com/automation/webhooks/jira/a/9617eefd-83a9-40b6-8346-8b8b444489e9/0198f4b0-f3e6-7d42-8c33-30cdd817af09"  # <<< วาง URL ของคุณ
$headers    = @{ "Content-Type" = "application/json" }
$json       = $payload | ConvertTo-Json -Depth 6

## --- post to Jira webhook (disabled for local test) ---
try {
  $resp = Invoke-RestMethod -Method POST -Uri $webhookUrl -Headers $headers -Body $json -TimeoutSec 30
  Write-Host "Posted OK"
} catch {
  Write-Error "Post failed: $($_.Exception.Message)"
}

# --- show output for local test ---
Write-Output $json
