# Jira AD Autofill (Native Extension)

เติมค่า AD username (sAMAccountName) ลง custom field บน Jira Cloud โดยใช้ Chrome/Edge Extension + Native Messaging (ไม่มี HTTP 127.0.0.1)

## Requirements
- Windows 10/11
- Google Chrome หรือ Microsoft Edge
- .NET SDK 8.0 (หรือ 6.0)
- เครื่อง join AD (เพื่อดึง sAMAccountName จาก Domain) — ถ้าไม่ join จะ fallback เป็น Environment.UserName

## Quickstart

### สำหรับ Google Chrome
1. โหลดส่วนขยายแบบ unpacked (โฟลเดอร์ `extension/`) และจด Extension ID
2. PowerShell:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\scripts\build.ps1
   .\scripts\install.ps1 -ExtensionId "<YOUR_EXTENSION_ID>"
   ```

### สำหรับ Microsoft Edge
1. เปิด Edge → `edge://extensions/`
2. เปิด "Developer mode"
3. คลิก "Load unpacked" → เลือกโฟลเดอร์ `extension/`
4. คัดลอก Extension ID ที่ Edge สร้างให้
5. PowerShell:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\scripts\build.ps1
   .\scripts\install.ps1 -ExtensionId "<YOUR_EDGE_EXTENSION_ID>"
   ```

### ตั้งค่าทั่วไป
1. เปิดหน้า Options ของส่วนขยาง ตั้งค่า:
   - Custom Field ID: เช่น `customfield_12345`
   - Field Label (fallback): เช่น `AD Username`
2. เปิด Jira → Create issue → ฟิลด์จะถูกเติมอัตโนมัติ (ถ้ามีค่าอยู่แล้วจะไม่ทับ)

## Uninstall
```powershell
.\scripts\uninstall.ps1
```

## Microsoft Edge Testing

### ขั้นตอนการทดสอบบน Edge

1. **โหลด Extension:**
   ```
   edge://extensions/ → Developer mode → Load unpacked → เลือกโฟลเดอร์ extension/
   ```

2. **คัดลอก Extension ID:**
   - จาก Edge extensions page (32 ตัวอักษร)

3. **ติดตั้ง Native Host:**
   ```powershell
   .\scripts\install.ps1 -ExtensionId "YOUR_EDGE_EXTENSION_ID"
   ```

4. **ทดสอบ URLs (แทนที่ Extension ID):**
   ```
   edge-extension://YOUR_EXTENSION_ID/options.html
   edge-extension://YOUR_EXTENSION_ID/debug-test.html
   edge-extension://YOUR_EXTENSION_ID/final-test.html
   ```

### ความแตกต่างระหว่าง Chrome และ Edge

| คุณสมบัติ | Chrome | Edge |
|----------|--------|------|
| Extensions URL | `chrome://extensions/` | `edge://extensions/` |
| Extension URL Scheme | `chrome-extension://` | `edge-extension://` |
| Native Messaging Registry | `HKCU\Software\Google\Chrome\NativeMessagingHosts` | `HKCU\Software\Microsoft\Edge\NativeMessagingHosts` |
| Extension ID Format | เหมือนกัน (32 ตัวอักษร) | เหมือนกัน (32 ตัวอักษร) |

### หมายเหตุสำหรับ Edge

- Edge ใช้ Chromium engine เหมือน Chrome ดังนั้น extension จะทำงานเหมือนกัน
- Native messaging manifest จะถูกลงทะเบียนใน registry ของ Edge แยกต่างหาก
- Script `install.ps1` รองรับทั้ง Chrome และ Edge registry
