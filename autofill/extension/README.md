Jira AD Autofill (HTTP whoami service)
======================================

This extension autofills a Jira field with the current Windows username by calling a local HTTP service provided by `whoami-service-main/service.py` on http://127.0.0.1:7777.

Included files
- manifest.json (MV3, allows http://127.0.0.1/*)
- background.js (fetches from http://127.0.0.1:7777/whoami)
- simple-content.js (autofills Jira field)
- options.html, options.js (configure field id/label, manual fallback)

Setup the local service (PowerShell as Administrator)
1) Install the service with Auto Start:
  - python d:\work\ad_to_jira\whoami-service-main\service.py --startup auto install
  - python d:\work\ad_to_jira\whoami-service-main\service.py start
  - Verify: curl http://127.0.0.1:7777/healthz (expect {"status":"ok"})

Load the extension (unpacked)
1) Chrome/Edge → enable Developer mode
2) Load unpacked → select this `extension` folder

Use
- Open Jira (https://*.atlassian.net/*)
- Configure via Options (Custom Field ID or Label)
- The script fills when the field appears

Troubleshooting
- If background shows HTTP errors, ensure the service is running and port 7777 is reachable
- Check http://127.0.0.1:7777/whoami in the browser to see JSON payload
