
# extension-chrome-automation
extension auto input value in browser
=======
# Autofill

Chrome/Edge extension ที่ช่วยเติม AD username ลงในฟิลด์ Jira อัตโนมัติ

## 🚀 การติดตั้งแบบ One-Click

# Extension Chrome Automation

Extension สำหรับ Chrome/Edge ที่ช่วยเติม AD/Windows username ลงในฟิลด์ Jira โดยดึงข้อมูลจากบริการภายในเครื่อง (HTTP) ที่พอร์ต 7777

แกนหลักของโปรเจกต์ตอนนี้เป็นโหมด HTTP ผ่าน `whoami-service-main/service.py` แล้ว ไม่ใช้ native messaging อีกต่อไป

## โครงสร้างสำคัญ
- `autofill/extension/` — ไฟล์ส่วนขยาย (Manifest V3)
- `webservice-new/service.py` — Windows Service (pywin32) ให้ HTTP endpoint

## เตรียมระบบ (Windows)
- ติดตั้ง Python 3.11+ และแพ็กเกจ pywin32
- เปิด PowerShell แบบ Run as Administrator

## ติดตั้งและรัน Whoami Service (HTTP)
1) ติดตั้งบริการให้เริ่มอัตโนมัติและสตาร์ต
```powershell
python .\webservice-new\service.py --startup auto install
python .\webservice-new\service.py start
```
2) ตรวจสุขภาพบริการ
```powershell
curl http://127.0.0.1:7777/healthz
```
3) ตัวอย่างข้อมูล
```powershell
curl http://127.0.0.1:7777/whoami
```

## โหลด Extension แบบ Unpacked
1) Chrome/Edge → เปิด Developer mode
2) Load unpacked → เลือกโฟลเดอร์ `webservice-new/extension`

สิทธิ์ที่ต้องอนุญาตใน manifest
- `https://*.atlassian.net/*`
- `http://127.0.0.1/*`

## ใช้งาน
- ตั้งค่าในหน้า Options: ระบุ Custom Field ID หรือใช้ Label fallback, ตั้งค่า manual username (ถ้าต้องการ)
- เข้า Jira (คลาวด์) แล้วเปิดหน้าสร้าง/แก้ไข issue ระบบจะพยายามเติมค่าให้โดยอัตโนมัติ

## Troubleshooting
- ถ้าไม่พบ username: เปิด `chrome://extensions/` → คลิก Service worker ของส่วนขยาย → ดู log ของ background ว่าดึง `http://127.0.0.1:7777/whoami` ผ่านหรือไม่
- ตรวจว่า Service ทำงานอยู่ และพอร์ต 7777 ไม่ถูกบล็อก
- ตรวจ endpoint ด้วยเบราว์เซอร์: http://127.0.0.1:7777/whoami

## หมายเหตุการย้ายโหมด
- โหมด native messaging และสคริปต์ที่เกี่ยวข้องถูกถอดออกแล้ว เพื่อลดความซับซ้อน
- หากต้องการโหมดเดิม แจ้งได้ จะเพิ่มสวิตช์ fallback ให้เลือกได้
