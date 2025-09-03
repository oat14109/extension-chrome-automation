<<<<<<< HEAD
# extension-chrome-automation
extension auto input value in browser
=======
# Jira AD Autofill

Chrome/Edge extension ที่ช่วยเติม AD username ลงในฟิลด์ Jira อัตโนมัติ

## 🚀 การติดตั้งแบบ One-Click

### ข้อกำหนดเบื้องต้น
- Windows 10/11
- .NET 8 SDK ([ดาวน์โหลดที่นี่](https://dotnet.microsoft.com/download/dotnet/8.0))
- Chrome หรือ Edge browser
- PowerShell with Administrator privileges

### การติดตั้ง
1. **รัน PowerShell as Administrator**
2. **เปลี่ยนไปยังโฟลเดอร์โปรเจกต์**
   ```powershell
   cd D:\work\ad_to_jira
   ```
3. **รันคำสั่งติดตั้ง**
   ```powershell
   .\INSTALL.ps1
   ```
4. **ทำตามคำแนะนำบนหน้าจอ**

### การโหลด Chrome Extension
หลังจากรัน INSTALL.ps1 แล้ว:
````markdown
# extension-chrome-automation

Autofill Jira fields with the current Windows username via a local HTTP service and a lightweight Chrome/Edge extension.

Quick start
- Start local whoami service (PowerShell as Administrator):
   - python .\whoami-service-main\service.py --startup auto install
   - python .\whoami-service-main\service.py start
   - Verify: open http://127.0.0.1:7777/healthz
- Load the extension (unpacked):
   - Chrome/Edge → Developer mode → Load unpacked → select `jira-ad-autofill/extension`
   - Configure Options (Custom Field ID or Label)

More details
- See `jira-ad-autofill/extension/README.md` for extension behavior and troubleshooting.
````
## 🎯 การใช้งาน
