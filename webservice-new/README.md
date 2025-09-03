# Whoami Service (Windows)

สคริปต์ช่วยจัดการสำหรับโปรเจกต์ `whoami-service` (Windows PowerShell)

ไฟล์สำคัญ
- `service.py` — โค้ด Python สำหรับรันเป็น Windows Service
- `install-service.ps1` — PowerShell เพื่อช่วยติดตั้ง dependency และ service
- `remove-service.ps1` — PowerShell สำหรับ stop/remove service

การเตรียมความพร้อม
1. ติดตั้ง Python 3.x และตรวจว่าคำสั่ง `python` หรือ `py` อยู่ใน PATH
2. เปิด PowerShell (แนะนำ Run as Administrator สำหรับคำสั่งที่ต้องติดตั้งหรือลงบริการ)



ตัวอย่างการใช้งาน (PowerShell)
```powershell
# ติดตั้ง dependency (จะยกระดับสิทธิ์เป็น Administrator หากจำเป็น)
.\install-service.ps1

# เอา service ออก
.\remove-service.ps1
```
---

## Manual Install
```powershell
pip install pywin32

sudo python service.py install
sudo python service.py --startup auto start

sudo python service.py stop
sudo python service.py remove
```
---

## How to use?
```
curl http://127.0.0.1:7777/
curl http://127.0.0.1:7777/active-user
curl http://127.0.0.1:7777/healthz
```