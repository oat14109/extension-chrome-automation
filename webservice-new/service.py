# service.py
import json
import logging
import os
import socket
import threading
import time
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import win32event
import win32service
import win32serviceutil
import servicemanager
import win32ts  # ใช้ดึง active console user

# ---------------- ปรับค่าได้ ----------------
HOST = os.environ.get("WHOAMI_HOST", "127.0.0.1")  # ใช้ "0.0.0.0" ถ้าต้องการรับจากภายนอก
PORT = int(os.environ.get("WHOAMI_PORT", "7777"))
LOG_PATH = os.path.join(
    os.environ.get("PROGRAMDATA", r"C:\ProgramData"),
    "whoami_service",
    "service.log",
)
# -------------------------------------------

logger = logging.getLogger("whoami_service")
logger.setLevel(logging.INFO)  # handler จะถูกเติมภายหลัง


def setup_logging():
    """สร้างโฟลเดอร์ log และผูก FileHandler อย่างปลอดภัย (เรียกเมื่อ service เริ่มจริง ๆ)"""
    try:
        log_dir = Path(LOG_PATH).parent
        log_dir.mkdir(parents=True, exist_ok=True)

        from logging.handlers import RotatingFileHandler
        fh = RotatingFileHandler(LOG_PATH, maxBytes=5_000_000, backupCount=3, encoding="utf-8")
        fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
        fh.setFormatter(fmt)

        logger.handlers.clear()
        logger.addHandler(fh)
        logger.propagate = False

        logger.info("Logging initialized at %s", LOG_PATH)
    except Exception:
        # ถ้าเขียน ProgramData ไม่ได้ ให้ fallback ไป temp
        import tempfile
        fallback = os.path.join(tempfile.gettempdir(), "whoami_service.log")
        try:
            from logging.handlers import RotatingFileHandler
            fh = RotatingFileHandler(fallback, maxBytes=5_000_000, backupCount=2, encoding="utf-8")
            fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
            fh.setFormatter(fmt)
            logger.handlers.clear()
            logger.addHandler(fh)
            logger.propagate = False
            logger.warning("Failed to init log at %s, fallback to %s", LOG_PATH, fallback)
        except Exception:
            pass  # อย่างน้อย Event Log ยังมี


def iso_now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def get_process_whoami() -> dict:
    """รัน whoami (ผู้ใช้ของโปรเซส service ปัจจุบัน)"""
    raw = ""
    try:
        proc = subprocess.run(["whoami"], capture_output=True, text=True, shell=False, check=True)
        raw = (proc.stdout or "").strip()
    except subprocess.CalledProcessError as e:
        logger.exception("whoami failed")
        raw = (e.stdout or "").strip() or "unknown"

    domain, username = (None, raw)
    if "\\" in raw:
        domain, username = raw.split("\\", 1)

    return {"raw": raw, "domain": domain, "username": username}


def get_active_console_user() -> dict | None:
    """
    คืนผู้ใช้ที่ล็อกอินหน้าเครื่อง (interactive console session)
    ถ้าไม่มี session จะคืน None
    """
    try:
        sid = win32ts.WTSGetActiveConsoleSessionId()
        if sid == 0xFFFFFFFF:
            return None
        username = win32ts.WTSQuerySessionInformation(None, sid, win32ts.WTSUserName)
        domain = win32ts.WTSQuerySessionInformation(None, sid, win32ts.WTSDomainName)
        if not username:
            return None
        return {"domain": domain, "username": username, "session_id": int(sid)}
    except Exception:
        logger.exception("Failed to query active console user")
        return None


class QuietHTTPServer(ThreadingHTTPServer):
    """เปิดใช้ SO_REUSEADDR และ thread daemon"""
    daemon_threads = True
    allow_reuse_address = True


class WhoamiHTTPRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logger.info("HTTP %s - " + fmt, self.address_string(), *args)

    def _send_json(self, obj: dict, status: int = 200):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/whoami"):
            payload = {
                "process_user": get_process_whoami(),
                "active_console_user": get_active_console_user(),
                "host": socket.gethostname(),
                "listen": {"host": HOST, "port": PORT},
                "ts": iso_now(),
            }
            return self._send_json(payload, 200)

        if self.path == "/active-user":
            payload = {
                "active_console_user": get_active_console_user(),
                "host": socket.gethostname(),
                "ts": iso_now(),
            }
            return self._send_json(payload, 200)

        if self.path == "/healthz":
            return self._send_json({"status": "ok", "ts": iso_now()}, 200)

        return self._send_json({"error": "not found"}, 404)


class WhoamiService(win32serviceutil.ServiceFramework):
    _svc_name_ = "PyWin32Whoami7777"
    _svc_display_name_ = "Python Whoami JSON Service (port 7777)"
    _svc_description_ = "HTTP service that returns whoami and active console user in JSON."

    def __init__(self, args):
        super().__init__(args)
        self.hWaitStop = win32event.CreateEvent(None, 0, 0, None)
        self.httpd: QuietHTTPServer | None = None
        self.server_thread: threading.Thread | None = None
        self.running = True

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        logger.info("Service stopping...")
        self.running = False
        try:
            if self.httpd:
                self.httpd.shutdown()
        except Exception:
            logger.exception("HTTP shutdown error")
        try:
            if self.httpd:
                self.httpd.server_close()
        except Exception:
            logger.exception("HTTP server_close error")
        win32event.SetEvent(self.hWaitStop)
        logger.info("Service stopped")

    def SvcDoRun(self):
        servicemanager.LogInfoMsg(f"{self._svc_name_} starting")
        setup_logging()
        logger.info("Service starting...")
        try:
            self.main()
        except Exception:
            logger.exception("Fatal error in service main")
            raise

    def main(self):
        self.httpd = QuietHTTPServer((HOST, PORT), WhoamiHTTPRequestHandler)
        self.server_thread = threading.Thread(
            target=self.httpd.serve_forever, kwargs={"poll_interval": 0.5}, daemon=True
        )
        self.server_thread.start()
        logger.info("HTTP server running on http://%s:%d", HOST, PORT)

        while self.running:
            rc = win32event.WaitForSingleObject(self.hWaitStop, 1000)
            if rc == win32event.WAIT_OBJECT_0:
                break

        logger.info("Main loop exit")


if __name__ == "__main__":
    # ตั้งค่าทุกอย่างตอนรันจริงใน SvcDoRun() เพื่อลด side-effects ตอน install/remove
    win32serviceutil.HandleCommandLine(WhoamiService)
