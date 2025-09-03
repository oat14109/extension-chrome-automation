@echo off
setlocal EnableDelayedExpansion

title AD Username HTTP Service - Official Installer
color 0B

:: Banner
echo.
echo ================================================================
echo            AD Username HTTP Service - Official Installer
echo ================================================================
echo.
echo Version: 1.0
echo Author: AD to Jira Extension Team
echo Date: September 2025
echo.
echo This installer will set up a background HTTP service to retrieve
echo Active Directory username for Jira autofill extension.
echo.
echo ================================================================
echo.

:: Check current directory
cd /d "%~dp0"
set "INSTALL_DIR=%~dp0"

echo Current installation directory: %INSTALL_DIR%
echo.

:: Main menu
:MAIN_MENU
echo ================================================================
echo                        MAIN MENU
echo ================================================================
echo.
echo 1. Install Background Service (Recommended)
echo 2. Test Server
echo 3. Uninstall Service
echo 4. Server Status
echo 5. Manual Start Server
echo 6. Exit
echo.
set /p choice="Please select an option (1-6): "

if "%choice%"=="1" goto INSTALL_SERVICE
if "%choice%"=="2" goto TEST_SERVER
if "%choice%"=="3" goto UNINSTALL_SERVICE
if "%choice%"=="4" goto SERVER_STATUS
if "%choice%"=="5" goto MANUAL_START
if "%choice%"=="6" goto EXIT

echo Invalid choice. Please try again.
echo.
goto MAIN_MENU

:: Install Service
:INSTALL_SERVICE
echo.
echo ================================================================
echo                    INSTALLING BACKGROUND SERVICE
echo ================================================================
echo.
echo This will install AD Username HTTP Service as a background service:
echo ✅ Runs completely in background (no windows)
echo ✅ Starts automatically when Windows starts
echo ✅ Auto-restarts if service crashes
echo ✅ Available at: http://127.0.0.1:7777/username
echo.
set /p confirm="Continue with installation? (Y/N): "
if /i not "%confirm%"=="Y" goto MAIN_MENU

echo.
echo Installing background service...

:: Check if Python is available
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ ERROR: Python not found!
    echo.
    echo Please install Python from: https://python.org
    echo Make sure to check "Add Python to PATH" during installation
    echo.
    pause
    goto MAIN_MENU
)

echo ✅ Python found

:: Check if required files exist
if not exist "ad_server.py" (
    echo ❌ ERROR: ad_server.py not found!
    echo Please ensure all files are in the same directory.
    pause
    goto MAIN_MENU
)

echo ✅ Server files found

:: Stop any existing services
echo Stopping existing services...
taskkill /f /im wscript.exe >nul 2>&1
taskkill /f /im python.exe >nul 2>&1

:: Remove old shortcuts
set "StartupFolder=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
del "%StartupFolder%\AD Username*.lnk" >nul 2>&1

:: Create VBScript runner if not exists
if not exist "run-background.vbs" (
    echo Creating background runner...
    (
    echo Set WshShell = CreateObject("WScript.Shell"^)
    echo Set objFSO = CreateObject("Scripting.FileSystemObject"^)
    echo.
    echo strScriptPath = objFSO.GetParentFolderName(WScript.ScriptFullName^)
    echo.
    echo WshShell.Run "cmd /c cd /d """ ^& strScriptPath ^& """ ^&^& python ad_server.py", 0, False
    echo.
    echo Do
    echo     WScript.Sleep 30000
    echo     Set objWMIService = GetObject("winmgmts:\\.\root\cimv2"^)
    echo     Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE Name = 'python.exe'"^)
    echo     bServerRunning = False
    echo     For Each objProcess in colProcesses
    echo         If InStr(objProcess.CommandLine, "ad_server.py"^) ^> 0 Then
    echo             bServerRunning = True
    echo             Exit For
    echo         End If
    echo     Next
    echo     If Not bServerRunning Then
    echo         WshShell.Run "cmd /c cd /d """ ^& strScriptPath ^& """ ^&^& python ad_server.py", 0, False
    echo     End If
    echo Loop
) > "run-background.vbs"
)

:: Create startup shortcut
echo Creating Windows Startup entry...
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%StartupFolder%\AD Username HTTP Service.lnk'); $Shortcut.TargetPath = '%INSTALL_DIR%run-background.vbs'; $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; $Shortcut.Description = 'AD Username HTTP Background Service'; $Shortcut.WindowStyle = 7; $Shortcut.Save()"

if %errorlevel% neq 0 (
    echo ❌ Failed to create startup shortcut
    pause
    goto MAIN_MENU
)

echo ✅ Windows Startup entry created

:: Start the service
echo Starting background service...
start /min "" wscript "%INSTALL_DIR%run-background.vbs"

:: Wait and test
echo Waiting for service to start...
timeout /t 5 >nul

:: Test if service is working
curl -s http://127.0.0.1:7777/username >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ Service started successfully!
) else (
    echo ⚠️  Service may be starting... (check in a moment)
)

echo.
echo ================================================================
echo                    INSTALLATION COMPLETE!
echo ================================================================
echo.
echo ✅ AD Username HTTP Service installed successfully!
echo ✅ Service will start automatically with Windows
echo ✅ Running in background (no windows will appear)
echo ✅ Auto-restart enabled if service crashes
echo.
echo Service Information:
echo • URL: http://127.0.0.1:7777/username
echo • Installation: %INSTALL_DIR%
echo • Startup: %StartupFolder%\AD Username HTTP Service.lnk
echo.
echo You can now use this service with the Jira autofill extension.
echo.
pause
goto MAIN_MENU

:: Test Server
:TEST_SERVER
echo.
echo ================================================================
echo                        TESTING SERVER
echo ================================================================
echo.
echo Testing AD Username HTTP Server...
echo.

curl -s http://127.0.0.1:7777/username >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ HTTP Server: RUNNING
    curl http://127.0.0.1:7777/username
) else (
    echo ❌ HTTP Server: NOT RUNNING
    echo.
    echo To start server:
    echo • Option 1: Install Background Service (option 1)
    echo • Option 2: Manual Start Server (option 5)
)

echo.
pause
goto MAIN_MENU

:: Uninstall Service
:UNINSTALL_SERVICE
echo.
echo ================================================================
echo                    UNINSTALLING SERVICE
echo ================================================================
echo.
echo This will remove the AD Username HTTP Service:
echo ❌ Stop all running processes
echo ❌ Remove from Windows Startup
echo ❌ Clean up service files
echo.
set /p confirm="Continue with uninstallation? (Y/N): "
if /i not "%confirm%"=="Y" goto MAIN_MENU

echo.
echo Uninstalling service...

:: Stop processes
echo Stopping background processes...
taskkill /f /im wscript.exe >nul 2>&1
taskkill /f /im python.exe >nul 2>&1
echo ✅ Processes stopped

:: Remove startup shortcut
echo Removing from Windows Startup...
set "StartupFolder=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
del "%StartupFolder%\AD Username*.lnk" >nul 2>&1
echo ✅ Startup entry removed

echo.
echo ================================================================
echo                    UNINSTALL COMPLETE!
echo ================================================================
echo.
echo ✅ AD Username HTTP Service has been uninstalled
echo ✅ Service will not start automatically anymore
echo ✅ All background processes stopped
echo.
echo To reinstall: Run this installer again and select option 1
echo.
pause
goto MAIN_MENU

:: Server Status
:SERVER_STATUS
echo.
echo ================================================================
echo                        SERVER STATUS
echo ================================================================
echo.

:: Check HTTP endpoint
echo Checking HTTP endpoint...
curl -s http://127.0.0.1:7777/username >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ HTTP Server: RUNNING
    echo Response: 
    curl -s http://127.0.0.1:7777/username
) else (
    echo ❌ HTTP Server: NOT RUNNING
)

echo.

:: Check Python processes
echo Checking Python processes...
tasklist /fi "imagename eq python.exe" 2>nul | findstr "python.exe" >nul
if %errorlevel% equ 0 (
    echo ✅ Python processes found:
    tasklist /fi "imagename eq python.exe" /fo table
) else (
    echo ❌ No Python processes running
)

echo.

:: Check VBScript processes
echo Checking background service...
tasklist /fi "imagename eq wscript.exe" 2>nul | findstr "wscript.exe" >nul
if %errorlevel% equ 0 (
    echo ✅ Background service VBScript running
) else (
    echo ❌ Background service not running
)

echo.

:: Check startup entry
echo Checking Windows Startup entry...
set "StartupFolder=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "%StartupFolder%\AD Username HTTP Service.lnk" (
    echo ✅ Startup entry exists
) else (
    echo ❌ Startup entry not found
)

echo.
pause
goto MAIN_MENU

:: Manual Start
:MANUAL_START
echo.
echo ================================================================
echo                    MANUAL START SERVER
echo ================================================================
echo.
echo Starting server in console mode...
echo Press Ctrl+C to stop the server
echo.
pause

if not exist "ad_server.py" (
    echo ❌ ERROR: ad_server.py not found!
    pause
    goto MAIN_MENU
)

python ad_server.py
pause
goto MAIN_MENU

:: Exit
:EXIT
echo.
echo ================================================================
echo                           GOODBYE!
echo ================================================================
echo.
echo Thank you for using AD Username HTTP Service!
echo.
echo For support and documentation, please check:
echo • README.md - Detailed documentation
echo • QUICK_START.md - Quick start guide
echo.
pause
exit /b 0
