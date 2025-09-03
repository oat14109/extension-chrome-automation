import sys
import os
import time
import threading
import signal
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
from datetime import datetime

# Windows Service imports
try:
    import win32serviceutil
    import win32service
    import win32event
    import servicemanager
    WINDOWS_SERVICE = True
except ImportError:
    WINDOWS_SERVICE = False
    print("Windows service modules not available. Install with: pip install pywin32")

# Server configuration
HOST = '127.0.0.1'
PORT = 7777

def _log(msg: str):
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(script_dir, 'service.log'), 'a', encoding='utf-8') as f:
            f.write(f"{datetime.now().isoformat()} | {msg}\n")
    except Exception:
        # Best-effort; ignore logging errors
        pass

def _script_dir():
    return os.path.dirname(os.path.abspath(__file__))

def _svc_name_path():
    return os.path.join(_script_dir(), 'service_name.txt')

# Early import marker for diagnostics (helps detect import failures under PythonService)
try:
    _log("module import: ad_server_service loaded")
    # Log key environment info to aid service startup debugging
    for k in ["PYTHONHOME", "PYTHONPATH", "Path", "PATH", "AppDirectory"]:
        try:
            v = os.environ.get(k)
            if v:
                _log(f"env {k}={v}")
        except Exception:
            pass
except Exception:
    pass

def _read_saved_service_name():
    try:
        with open(_svc_name_path(), 'r', encoding='utf-8') as f:
            name = f.read().strip()
            return name or None
    except Exception:
        return None

def _write_saved_service_name(name: str):
    try:
        with open(_svc_name_path(), 'w', encoding='utf-8') as f:
            f.write(name)
    except Exception as e:
        _log(f"Failed to write service_name.txt: {e}")

class ADUsernameHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/username':
            try:
                username = self.get_ad_username()
                response = {
                    "ok": True,
                    "username": username,
                    "method": "AD"
                }
            except Exception as e:
                response = {
                    "ok": False,
                    "error": str(e)
                }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/' or self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            response = {
                "service": "AD Username HTTP Server",
                "status": "running",
                "endpoint": f"http://{HOST}:{PORT}/username"
            }
            self.wfile.write(json.dumps(response).encode())
        
        else:
            self.send_response(404)
            self.end_headers()

    def get_ad_username(self):
        """Get AD username (sAMAccountName) from domain"""
        
        # Method 1: Get logged-in user via explorer.exe process (works even in service mode)
        try:
            cmd = [
                'powershell', '-Command',
                'Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | '
                'Where-Object {$_.UserName -and $_.UserName -notlike "*$"} | '
                'Select-Object -First 1 -ExpandProperty UserName | '
                'ForEach-Object { $_.Split("\\")[-1] }'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                username = result.stdout.strip()
                if username and username.lower() not in ['system', 'local service', 'network service']:
                    return username
        except Exception:
            pass
        
        # Method 2: Get active console session user
        try:
            cmd = [
                'powershell', '-Command',
                'query user | Select-String "Active" | ForEach-Object { ($_ -split "\\s+")[1] }'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                username = result.stdout.strip()
                if username and username.lower() not in ['system', 'local service', 'network service']:
                    return username
        except Exception:
            pass
        
        # Method 3: Try PowerShell Get-ADUser (requires RSAT) - only if not system account
        try:
            cmd = [
                'powershell', '-Command',
                'try { Import-Module ActiveDirectory -ErrorAction Stop; '
                '(Get-ADUser -Identity $env:USERNAME).sAMAccountName } '
                'catch { $env:USERNAME }'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                username = result.stdout.strip()
                if username and username.lower() not in ['system', 'local service', 'network service']:
                    return username
        except Exception:
            pass
        
        # Method 4: Try whoami command (fallback)
        try:
            cmd = ['whoami']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                # Extract username from DOMAIN\username format
                username = result.stdout.strip()
                if '\\' in username:
                    username = username.split('\\')[-1]
                if username and username.lower() not in ['system', 'local service', 'network service']:
                    return username
        except Exception:
            pass
        
        # Method 5: Environment variable (last resort)
        username = os.environ.get('USERNAME', 'unknown')
        if username.lower() not in ['system', 'local service', 'network service']:
            return username
        
        # If all methods return system accounts, return a default
        return 'unknown'

    def is_domain_joined(self):
        """Check if computer is joined to domain"""
        try:
            cmd = ['systeminfo']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                return 'Domain:' in result.stdout and 'WORKGROUP' not in result.stdout
        except Exception:
            pass
        return False

    def log_message(self, format, *args):
        """Custom log format"""
        print(f"[{self.date_time_string()}] {format % args}")

class ADUsernameServer:
    def __init__(self):
        self.httpd = None
        self.server_thread = None
        self.stop_event = threading.Event()

    def start(self):
        try:
            _log("ADUsernameServer.start: invoked")
            # Close any existing server
            if self.httpd:
                self.stop()
            
            # Create new server
            self.httpd = HTTPServer((HOST, PORT), ADUsernameHandler)
            self.server_thread = threading.Thread(target=self._run_server)
            self.server_thread.daemon = True
            self.server_thread.start()
            _log("ADUsernameServer.start: thread started; sleeping 1s")
            
            # Give the server more time to start in service context
            time.sleep(1)
            
            # Check if the server actually started
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                sock.settimeout(5)
                result = sock.connect_ex((HOST, PORT))
                sock.close()
                if result == 0:
                    _log(f"ADUsernameServer.start: server reachable on {HOST}:{PORT}")
                    print(f"Server started successfully on {HOST}:{PORT}")
                    return True
                else:
                    _log(f"ADUsernameServer.start: connect_ex returned {result}")
                    print(f"Failed to connect to server on {HOST}:{PORT}")
                    return False
            except Exception as e:
                _log(f"ADUsernameServer.start: error checking server status: {e}")
                print(f"Error checking server status: {e}")
                return False
            
        except Exception as e:
            _log(f"ADUsernameServer.start: exception {e}")
            print(f"Failed to start server: {e}")
            import traceback
            tb = traceback.format_exc()
            print(f"Traceback: {tb}")
            _log(f"ADUsernameServer.start: traceback {tb}")
            return False

    def stop(self):
        self.stop_event.set()
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
        if self.server_thread:
            self.server_thread.join(timeout=5)

    def _run_server(self):
        try:
            self.httpd.serve_forever()
        except Exception as e:
            print(f"Server error: {e}")

# Windows Service Class
if WINDOWS_SERVICE:
    _DEFAULT_SVC_NAME = "ADUsernameHTTPService"
    _saved_name = _read_saved_service_name()
    class ADUsernameService(win32serviceutil.ServiceFramework):
        _svc_name_ = _saved_name or _DEFAULT_SVC_NAME
        _svc_display_name_ = f"AD Username HTTP Service"
        _svc_description_ = "HTTP service to retrieve Active Directory username for applications"

        def __init__(self, args):
            win32serviceutil.ServiceFramework.__init__(self, args)
            self.hWaitStop = win32event.CreateEvent(None, 0, 0, None)
            self.server = ADUsernameServer()
            try:
                _log(f"Service __init__: svc_name={self._svc_name_} args={args}")
            except Exception:
                pass

        def SvcStop(self):
            self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
            win32event.SetEvent(self.hWaitStop)
            self.server.stop()

        def SvcDoRun(self):
            # Report that we're starting
            self.ReportServiceStatus(win32service.SERVICE_START_PENDING)
            _log("SvcDoRun: START_PENDING reported")
            
            servicemanager.LogMsg(
                servicemanager.EVENTLOG_INFORMATION_TYPE,
                servicemanager.PYS_SERVICE_STARTED,
                (self._svc_name_, '')
            )
            
            try:
                # Set working directory to script location
                script_dir = os.path.dirname(os.path.abspath(__file__))
                os.chdir(script_dir)
                _log(f"SvcDoRun: chdir to {script_dir}")
                
                # Log startup attempt
                servicemanager.LogInfoMsg(f"Starting AD Username HTTP Service from {script_dir}")
                _log("SvcDoRun: calling server.start()")
                
                if self.server.start():
                    # Report that we're running successfully
                    self.ReportServiceStatus(win32service.SERVICE_RUNNING)
                    _log("SvcDoRun: SERVICE_RUNNING reported")
                    servicemanager.LogInfoMsg(f"AD Username HTTP Service started on http://{HOST}:{PORT}")
                    # Wait for stop signal
                    win32event.WaitForSingleObject(self.hWaitStop, win32event.INFINITE)
                    _log("SvcDoRun: stop signal received; exiting")
                else:
                    _log("SvcDoRun: server.start() returned False")
                    servicemanager.LogErrorMsg("Failed to start AD Username HTTP Service - server.start() returned False")
                    self.ReportServiceStatus(win32service.SERVICE_STOPPED)
            except Exception as e:
                servicemanager.LogErrorMsg(f"Service error: {str(e)}")
                import traceback
                tb = traceback.format_exc()
                servicemanager.LogErrorMsg(f"Traceback: {tb}")
                _log(f"SvcDoRun: exception {e}\n{tb}")
                self.ReportServiceStatus(win32service.SERVICE_STOPPED)

def install_service(name: str | None = None):
    """Install the Windows service"""
    if not WINDOWS_SERVICE:
        print("Error: Windows service modules not available")
        print("Install with: pip install pywin32")
        return False
    
    try:
        # Install service using PythonService.exe and the correct module path
        python_class = "ad_server_service.ADUsernameService"
        # Determine service name (dynamic by default)
        if not name:
            # Allow override via env var
            name = os.environ.get('SERVICE_NAME')
        if not name:
            user = os.environ.get('USERNAME') or 'svc'
            ts = datetime.now().strftime('%Y%m%d%H%M%S')
            name = f"ADUsernameHTTPService-{user}-{PORT}-{ts}"
        # Persist for future start/stop/status and for runtime class mapping
        _write_saved_service_name(name)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(script_dir)

        # Locate PythonService.exe with preference for base install (accessible to LocalSystem)
        pythonservice_candidates = []
        # 1) Explicit override via env var
        override_path = os.environ.get('SERVICE_PYTHONSERVICE')
        if override_path:
            pythonservice_candidates.append(override_path)
        # 2) Base/system Python site-packages (prefer these over user-site)
        for base in [p for p in [sys.base_prefix, sys.exec_prefix, sys.prefix] if p]:
            pythonservice_candidates.append(os.path.join(base, 'Lib', 'site-packages', 'win32', 'PythonService.exe'))
            pythonservice_candidates.append(os.path.join(base, 'Lib', 'site-packages', 'pywin32_system32', 'PythonService.exe'))
            pythonservice_candidates.append(os.path.join(base, 'Lib', 'site-packages', 'win32', 'pythonservice.exe'))
            pythonservice_candidates.append(os.path.join(base, 'Lib', 'site-packages', 'pywin32_system32', 'pythonservice.exe'))
        # 3) Scripts folder alongside python.exe
        python_dir = os.path.dirname(sys.executable)
        pythonservice_candidates.append(os.path.join(python_dir, 'PythonService.exe'))
        pythonservice_candidates.append(os.path.join(python_dir, 'pythonservice.exe'))
        # 4) Typical system locations installed by pywin32 postinstall
        system_root = os.environ.get('SystemRoot', r'C:\Windows')
        pythonservice_candidates.append(os.path.join(system_root, 'pywin32_system32', 'PythonService.exe'))
        pythonservice_candidates.append(os.path.join(system_root, 'System32', 'pywin32_system32', 'PythonService.exe'))
        # 5) Site-packages of current interpreter (user site LAST)
        try:
            import site
            # Only add user-site at the end to avoid LocalSystem ACL issues
            try:
                usp = site.getusersitepackages()
                pythonservice_candidates.append(os.path.join(usp, 'win32', 'PythonService.exe'))
                pythonservice_candidates.append(os.path.join(usp, 'pywin32_system32', 'PythonService.exe'))
                pythonservice_candidates.append(os.path.join(usp, 'win32', 'pythonservice.exe'))
                pythonservice_candidates.append(os.path.join(usp, 'pywin32_system32', 'pythonservice.exe'))
            except Exception:
                pass
            # Also include global site-packages from getsitepackages (already mostly covered by base), but keep after base
            try:
                for sp in site.getsitepackages():
                    pythonservice_candidates.append(os.path.join(sp, 'win32', 'PythonService.exe'))
                    pythonservice_candidates.append(os.path.join(sp, 'pywin32_system32', 'PythonService.exe'))
                    pythonservice_candidates.append(os.path.join(sp, 'win32', 'pythonservice.exe'))
                    pythonservice_candidates.append(os.path.join(sp, 'pywin32_system32', 'pythonservice.exe'))
            except Exception:
                pass
        except Exception:
            pass

        pythonservice_path = next((p for p in pythonservice_candidates if os.path.isfile(p)), None)

        # If PythonService.exe lives under a user profile, copy it to script_dir so LocalSystem can access it
        if pythonservice_path:
            try:
                lower_path = pythonservice_path.lower()
                if ('\\users\\' in lower_path or '/users/' in lower_path) and not pythonservice_path.lower().startswith(_script_dir().lower()):
                    dst = os.path.join(script_dir, 'PythonService.exe')
                    import shutil
                    shutil.copy2(pythonservice_path, dst)
                    pythonservice_path = dst
                    print(f"Info: Copied PythonService.exe to {dst} for LocalSystem access")
            except Exception as e:
                print(f"Warning: Could not copy PythonService.exe locally: {e}")

        if pythonservice_path:
            win32serviceutil.InstallService(
                pythonClassString=python_class,
                serviceName=name,
                displayName=f"AD Username HTTP Service ({name})",
                description=ADUsernameService._svc_description_,
                startType=win32service.SERVICE_AUTO_START,
                exeName=pythonservice_path
            )
            print(f"Using PythonService.exe: {pythonservice_path}")
        else:
            # Fallback to default behavior (let pywin32 resolve), but warn
            print("Warning: PythonService.exe not found explicitly; using default pywin32 resolution")
            win32serviceutil.InstallService(
                pythonClassString=python_class,
                serviceName=name,
                displayName=f"AD Username HTTP Service ({name})",
                description=ADUsernameService._svc_description_,
                startType=win32service.SERVICE_AUTO_START
            )

        # Ensure the service can import this module by setting PythonHome/PythonPath and working directory
        try:
            # PythonHome should be the base installation (contains python311.dll)
            py_home = sys.base_prefix or sys.prefix
            # Build a conservative PythonPath: stdlib, site-packages, and our project dirs
            candidate_paths = []
            if py_home:
                candidate_paths.extend([
                    os.path.join(py_home, 'Lib'),
                    os.path.join(py_home, 'Lib', 'site-packages'),
                    os.path.join(py_home, 'DLLs'),
                ])
            candidate_paths.extend([script_dir, project_root])
            # Deduplicate while preserving order
            seen = set()
            py_path = ";".join([p for p in candidate_paths if p and not (p in seen or seen.add(p))])

            if py_home:
                win32serviceutil.SetServiceCustomOption(name, "PythonHome", py_home)
            win32serviceutil.SetServiceCustomOption(name, "PythonPath", py_path)
            win32serviceutil.SetServiceCustomOption(name, "AppDirectory", script_dir)
            print(f"Set service options for {name}:")
            print(f"  PythonHome: {py_home}")
            print(f"  PythonPath: {py_path}")
            print(f"  AppDirectory: {script_dir}")
        except Exception as e:
            print(f"Warning: Could not set PythonHome/PythonPath/AppDirectory: {e}")

        # Set per-service environment variables to ensure python DLLs resolve under LocalSystem
        try:
            import winreg
            svc_key_path = fr"SYSTEM\CurrentControlSet\Services\{name}"
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, svc_key_path, 0, winreg.KEY_SET_VALUE | winreg.KEY_QUERY_VALUE) as k:
                env_vals = []
                try:
                    existing, regtype = winreg.QueryValueEx(k, 'Environment')
                    if regtype == winreg.REG_MULTI_SZ and isinstance(existing, list):
                        env_vals.extend(existing)
                except FileNotFoundError:
                    pass
                # Remove any prior PYTHONHOME/PYTHONPATH/Path entries
                def not_starts(prefix):
                    pl = prefix.lower()
                    return [v for v in env_vals if not v.lower().startswith(pl)]
                env_vals = not_starts('PYTHONHOME=')
                env_vals = not_starts('PYTHONPATH=')
                env_vals = not_starts('PATH=')
                # Compose new entries
                if py_home:
                    dlls = os.path.join(py_home, 'DLLs')
                    site_pkgs = os.path.join(py_home, 'Lib', 'site-packages')
                    pywin32_sys = os.path.join(site_pkgs, 'pywin32_system32')
                    win32_pkg = os.path.join(site_pkgs, 'win32')
                    # Ensure script_dir is also on PATH so co-located DLLs are found
                    path_parts = [p for p in [script_dir, py_home, dlls, pywin32_sys, win32_pkg] if p]
                    env_vals.append(f"PYTHONHOME={py_home}")
                    env_vals.append(f"PYTHONPATH={py_path}")
                    # Prepend dirs to PATH while preserving current machine PATH
                    machine_path = os.environ.get('Path', '')
                    prepend = ";".join(path_parts)
                    new_path = f"{prepend};{machine_path}" if machine_path else prepend
                    env_vals.append(f"PATH={new_path}")
                # Write back
                winreg.SetValueEx(k, 'Environment', 0, winreg.REG_MULTI_SZ, env_vals)
                print("Configured service-specific Environment variables (PYTHONHOME, PYTHONPATH, PATH)")
        except Exception as e:
            print(f"Warning: Could not set per-service Environment variables: {e}")

        # Set service to restart on failure
        try:
            import win32con
        except Exception:
            win32con = None
        try:
            hscm = win32service.OpenSCManager(None, None, win32service.SC_MANAGER_ALL_ACCESS)
            hs = win32service.OpenService(hscm, name, win32service.SERVICE_ALL_ACCESS)
            
            # Configure service to restart on failure
            restart_action = win32service.SC_ACTION_RESTART
            action_list = [(restart_action, 5000), (restart_action, 5000), (win32service.SC_ACTION_NONE, 0)]
            
            win32service.ChangeServiceConfig2(hs, win32service.SERVICE_CONFIG_FAILURE_ACTIONS, {
                'ResetPeriod': 86400,  # 24 hours
                'RebootMsg': '',
                'Command': '',
                'Actions': action_list
            })
            
            win32service.CloseServiceHandle(hs)
            win32service.CloseServiceHandle(hscm)
        except Exception as e:
            print(f"Warning: Could not set recovery options: {e}")
        
        print("Service will run as LocalSystem with enhanced username detection.")
        
        # If we are using a local PythonService.exe, also copy pythonXY.dll and pywin32 DLLs next to it to satisfy loader
        try:
            if pythonservice_path and os.path.dirname(pythonservice_path).lower() == script_dir.lower():
                maj, min = sys.version_info[:2]
                py_dll = os.path.join(sys.base_prefix or sys.prefix, f"python{maj}{min}.dll")
                if os.path.isfile(py_dll):
                    dst = os.path.join(script_dir, os.path.basename(py_dll))
                    if not os.path.isfile(dst):
                        import shutil
                        shutil.copy2(py_dll, dst)
                        print(f"Copied {py_dll} -> {dst}")
                # Copy pythoncomXY.dll and pywintypesXY.dll from site-packages\pywin32_system32 if available
                try:
                    import site
                    candidates = []
                    try:
                        for sp in site.getsitepackages():
                            candidates.append(os.path.join(sp, 'pywin32_system32'))
                    except Exception:
                        pass
                    try:
                        usp = site.getusersitepackages()
                        candidates.append(os.path.join(usp, 'pywin32_system32'))
                    except Exception:
                        pass
                    dll_names = [f"pythoncom{maj}{min}.dll", f"pywintypes{maj}{min}.dll"]
                    for base in candidates:
                        for dn in dll_names:
                            src = os.path.join(base, dn)
                            if os.path.isfile(src):
                                dst = os.path.join(script_dir, dn)
                                if not os.path.isfile(dst):
                                    import shutil
                                    shutil.copy2(src, dst)
                                    print(f"Copied {src} -> {dst}")
                except Exception as e:
                    print(f"Warning: Could not copy pywin32 DLLs: {e}")
        except Exception as e:
            print(f"Warning: Could not copy python DLL next to PythonService.exe: {e}")

        print(f"[SUCCESS] Service 'AD Username HTTP Service' installed successfully")
        print("   - Start type: Manual")
        print("   - Recovery: Restart on failure")
        print(f"   - Endpoint: http://{HOST}:{PORT}/username")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to install service: {e}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        return False
def uninstall_service():
    """Uninstall the Windows service"""
    if not WINDOWS_SERVICE:
        print("Error: Windows service modules not available")
        return False
    
    try:
        name = _read_saved_service_name() or "ADUsernameHTTPService"
        win32serviceutil.RemoveService(name)
        print(f"[SUCCESS] Service 'AD Username HTTP Service' uninstalled successfully")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to uninstall service: {e}")
        return False

def start_service():
    """Start the Windows service"""
    if not WINDOWS_SERVICE:
        print("Error: Windows service modules not available")
        return False
    
    try:
        name = _read_saved_service_name() or "ADUsernameHTTPService"
        win32serviceutil.StartService(name)
        print(f"[SUCCESS] Service 'AD Username HTTP Service' started successfully")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to start service: {e}")
        return False

def stop_service():
    """Stop the Windows service"""
    if not WINDOWS_SERVICE:
        print("Error: Windows service modules not available")
        return False
    
    try:
        name = _read_saved_service_name() or "ADUsernameHTTPService"
        win32serviceutil.StopService(name)
        print(f"[SUCCESS] Service 'AD Username HTTP Service' stopped successfully")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to stop service: {e}")
        return False

def service_status():
    """Check Windows service status"""
    if not WINDOWS_SERVICE:
        print("Windows service modules not available")
        return
    
    try:
        name = _read_saved_service_name() or "ADUsernameHTTPService"
        status = win32serviceutil.QueryServiceStatus(name)
        state = status[1]
        
        states = {
            win32service.SERVICE_STOPPED: "STOPPED",
            win32service.SERVICE_START_PENDING: "START_PENDING", 
            win32service.SERVICE_STOP_PENDING: "STOP_PENDING",
            win32service.SERVICE_RUNNING: "RUNNING",
            win32service.SERVICE_CONTINUE_PENDING: "CONTINUE_PENDING",
            win32service.SERVICE_PAUSE_PENDING: "PAUSE_PENDING",
            win32service.SERVICE_PAUSED: "PAUSED"
        }
        
        state_name = states.get(state, f"UNKNOWN({state})")
        print(f"Service Status: {state_name}")
        
        if state == win32service.SERVICE_RUNNING:
            print(f"[SUCCESS] Service is running")
            print(f"   Endpoint: http://{HOST}:{PORT}/username")
        else:
            print(f"[ERROR] Service is not running")
            
    except Exception as e:
        print(f"[ERROR] Service not found or error: {e}")

def run_console():
    """Run server in console mode"""
    print("Starting AD Username HTTP Server...")
    print(f"Server: http://{HOST}:{PORT}/")
    print(f"Endpoint: http://{HOST}:{PORT}/username")
    print(f"Working directory: {os.getcwd()}")
    print(f"Python executable: {sys.executable}")
    print("Press Ctrl+C to stop")
    print("-" * 50)
    
    server = ADUsernameServer()
    
    def signal_handler(sig, frame):
        print("\nShutting down server...")
        server.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    
    if server.start():
        try:
            while not server.stop_event.is_set():
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nReceived Ctrl+C, shutting down...")
        finally:
            server.stop()
    else:
        print("Failed to start server")
        sys.exit(1)

def debug_service():
    """Debug service installation and environment"""
    print("=== Service Debug Information ===")
    print(f"Python executable: {sys.executable}")
    print(f"Script path: {os.path.abspath(__file__)}")
    print(f"Working directory: {os.getcwd()}")
    print(f"Windows Service support: {WINDOWS_SERVICE}")
    
    if WINDOWS_SERVICE:
        try:
            status = win32serviceutil.QueryServiceStatus(ADUsernameService._svc_name_)
            print(f"Service exists: Yes")
            print(f"Service status: {status}")
        except Exception as e:
            print(f"Service exists: No ({e})")
    
    # Test server start
    print("\n=== Testing Server Start ===")
    server = ADUsernameServer()
    if server.start():
        print("✓ Server started successfully")
        server.stop()
        print("✓ Server stopped successfully")
    else:
        print("✗ Server failed to start")
    
    print("\n=== Network Test ===")
    import socket
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = sock.bind((HOST, PORT))
        sock.close()
        print(f"✓ Port {PORT} is available")
    except Exception as e:
        print(f"✗ Port {PORT} error: {e}")
    
    print("=== Debug Complete ===")

def main():
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        
        if command == 'install':
            install_service()
        elif command in ['remove', 'uninstall']:
            uninstall_service()
        elif command == 'start':
            start_service()
        elif command == 'stop':
            stop_service()
        elif command == 'status':
            service_status()
        elif command == 'console':
            run_console()
        elif command == 'debug':
            debug_service()
        else:
            print("Usage:")
            print("  python ad_server_service.py install    - Install Windows service")
            print("  python ad_server_service.py remove     - Uninstall Windows service")
            print("  python ad_server_service.py start      - Start Windows service")
            print("  python ad_server_service.py stop       - Stop Windows service") 
            print("  python ad_server_service.py status     - Check service status")
            print("  python ad_server_service.py console    - Run in console mode")
            print("  python ad_server_service.py debug      - Debug service setup")
            print("  python ad_server_service.py            - Run in console mode (default)")
    else:
        # Default: run in console mode
        run_console()

if __name__ == '__main__':
    main()
