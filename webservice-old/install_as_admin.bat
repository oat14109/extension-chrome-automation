@echo off
echo Installing AD Username Service with Auto Startup and Current User Account...
echo.
PowerShell.exe -Command "Start-Process python -ArgumentList 'ad_server_service.py install' -Verb RunAs -Wait"
echo.
echo Installation completed. Checking service status...
python ad_server_service.py status
echo.
pause
