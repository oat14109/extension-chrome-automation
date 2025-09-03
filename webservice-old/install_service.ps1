# AD Username Service - Enhanced Installer & Manager
# This script handles service installation with pywin32 setup and basic management

param(
    [Parameter(Position=0)]
    [ValidateSet("install", "uninstall", "clean", "start", "stop", "restart", "status", "test", "simple", "background", "help")]
    [string]$Action = "install"
)

# Configuration
$ServiceName = "ADUsernameHTTPService-ronnawit_s-7777-20250902184450"
$ServiceDisplayName = "AD Username HTTP Service"
$ServicePort = 7777
$ServiceHost = "127.0.0.1"

# Get script directory and set working directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminElevation {
    if (-not (Test-Administrator)) {
        Write-Host "[INFO] Administrator privileges required. Elevating..." -ForegroundColor Yellow
        try {
            # Get the full path to the current script
            $scriptPath = $MyInvocation.MyCommand.Path
            if (-not $scriptPath) {
                $scriptPath = Join-Path $scriptDir "install_service.ps1"
            }
            
            Start-Process PowerShell -Verb RunAs -ArgumentList @(
                "-ExecutionPolicy", "Bypass",
                "-NoExit",
                "-Command", "Set-Location '$scriptDir'; & '$scriptPath' $Action"
            )
            exit
        }
        catch {
            Write-Host "[ERROR] Failed to elevate to Administrator: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Please run PowerShell as Administrator manually." -ForegroundColor Yellow
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

function Stop-ConflictingProcesses {
    Write-Host "[INFO] Checking for conflicting processes on port $ServicePort..." -ForegroundColor Blue
    
    # Stop any Python processes running our service files
    $pythonProcesses = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*ad_server*" -or $_.MainWindowTitle -like "*ad_server*"
    }
    
    if ($pythonProcesses) {
        Write-Host "[INFO] Found Python processes running AD server:" -ForegroundColor Yellow
        $pythonProcesses | ForEach-Object {
            Write-Host "  - Stopping Python PID $($_.Id)" -ForegroundColor Gray
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }
    
    # Check for any processes using our port
    $processes = netstat -ano | findstr "$ServicePort" | findstr "LISTENING"
    if ($processes) {
        Write-Host "[WARNING] Found processes using port ${ServicePort}:" -ForegroundColor Yellow
        $processes | ForEach-Object {
            if ($_ -match '\s+(\d+)$') {
                $processId = $matches[1]
                try {
                    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                    if ($process) {
                        Write-Host "  - Stopping PID $processId ($($process.ProcessName))" -ForegroundColor Gray
                        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                    }
                }
                catch {
                    Write-Host "  - Could not stop process $processId" -ForegroundColor Red
                }
            }
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Host "[INFO] No conflicting processes found" -ForegroundColor Green
    }
}

function Install-ServiceComplete {
    Request-AdminElevation
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "AD Username Service - Complete Installer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Verify service file exists
    if (-not (Test-Path "ad_server_service.py")) {
        Write-Host "[ERROR] ad_server_service.py not found!" -ForegroundColor Red
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host "[SUCCESS] Running with Administrator privileges" -ForegroundColor Green
    Write-Host "[INFO] Working directory: $scriptDir" -ForegroundColor Blue
    Write-Host ""
    
    # Stop any existing services or processes
    Write-Host "[INFO] Cleaning up existing services..." -ForegroundColor Blue
    try {
        # Check if service exists first
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            & python ad_server_service.py stop 2>$null
        } else {
            Write-Host "[INFO] Service does not exist, skipping stop" -ForegroundColor Gray
        }
    } catch {
        Write-Host "[INFO] Service stop skipped" -ForegroundColor Gray
    }
    
    Stop-ConflictingProcesses
    
    # Uninstall existing service if it exists
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host "[INFO] Uninstalling existing service..." -ForegroundColor Blue
            & python ad_server_service.py uninstall 2>$null
            Start-Sleep -Seconds 2
        } else {
            Write-Host "[INFO] No existing service to uninstall" -ForegroundColor Gray
        }
    } catch {
        Write-Host "[INFO] Service uninstall skipped" -ForegroundColor Gray
    }
    
    # Run pywin32 post-install to ensure Windows service integration works
    Write-Host "[INFO] Setting up pywin32 for Windows service..." -ForegroundColor Blue
    try {
        $pywin32Output = & python -c "import sys; sys.path.append(r'C:\Python311\Scripts'); import pywin32_postinstall; pywin32_postinstall.install()" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] pywin32 setup completed" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] pywin32 setup returned non-zero exit code, trying alternative method..." -ForegroundColor Yellow
            try {
                & pywin32_postinstall.exe -install 2>&1 | Out-Null
                Write-Host "[SUCCESS] pywin32 setup completed via executable" -ForegroundColor Green
            } catch {
                Write-Host "[WARNING] Could not run pywin32_postinstall, continuing anyway..." -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "[WARNING] pywin32 setup failed, continuing with service installation..." -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Install the service
    Write-Host "[INFO] Installing $ServiceDisplayName..." -ForegroundColor Blue
    $installOutput = & python ad_server_service.py install 2>&1
    Write-Host $installOutput
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCESS] Service installed successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Start the service with retries
        $maxRetries = 3
        $serviceStarted = $false
        
        for ($i = 1; $i -le $maxRetries; $i++) {
            Write-Host "[INFO] Starting service (attempt $i of $maxRetries)..." -ForegroundColor Blue
            
            $startOutput = & python ad_server_service.py start 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $serviceStarted = $true
                break
            }
            
            # Handle timeout error - check if service is actually running
            if ($startOutput -like "*1053*") {
                Write-Host "[WARNING] Service startup timeout, checking actual status..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                
                # Test if endpoint is responding
                try {
                    $response = Invoke-RestMethod -Uri "http://$ServiceHost`:$ServicePort/username" -TimeoutSec 5
                    Write-Host "[SUCCESS] Service is actually running (despite timeout)" -ForegroundColor Green
                    $serviceStarted = $true
                    break
                }
                catch {
                    Write-Host "[INFO] Service not responding yet..." -ForegroundColor Gray
                }
            }
            
            if ($i -lt $maxRetries) {
                Write-Host "[INFO] Retrying in 3 seconds..." -ForegroundColor Blue
                Start-Sleep -Seconds 3
            }
        }
        
        if ($serviceStarted) {
            Write-Host ""
            Write-Host "[SUCCESS] Service is running!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Service Details:" -ForegroundColor White
            Write-Host "- Service Name: $ServiceName" -ForegroundColor Gray
            Write-Host "- Display Name: $ServiceDisplayName" -ForegroundColor Gray
            Write-Host "- Endpoint: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Gray
            Write-Host "- Auto-start: Enabled" -ForegroundColor Gray
            Write-Host ""
            
            # Test the endpoint
            Write-Host "[INFO] Testing endpoint..." -ForegroundColor Blue
            try {
                $response = Invoke-RestMethod -Uri "http://$ServiceHost`:$ServicePort/username" -TimeoutSec 10
                Write-Host "[SUCCESS] Service test passed!" -ForegroundColor Green
                Write-Host "Username: $($response.username)" -ForegroundColor White
                Write-Host "Method: $($response.method)" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Installation completed successfully! 🎉" -ForegroundColor Green
            }
            catch {
                Write-Host "[WARNING] Endpoint test failed, but service should be running" -ForegroundColor Yellow
                Write-Host "You can test manually at: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Cyan
            }
        } else {
            Write-Host ""
            Write-Host "[ERROR] Failed to start service after $maxRetries attempts" -ForegroundColor Red
            Write-Host "Service installed but not running. You can try:" -ForegroundColor Yellow
            Write-Host "  .\install_service.ps1 start" -ForegroundColor Gray
        }
    } else {
        Write-Host ""
        Write-Host "[ERROR] Failed to install service" -ForegroundColor Red
        Write-Host "Please check the error messages above" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Available commands:" -ForegroundColor White
    Write-Host "  .\install_service.ps1 status    - Check status" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 start     - Start service" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 stop      - Stop service" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 restart   - Restart service" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 test      - Test endpoint" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 uninstall - Remove service" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Press Enter to exit"
}

function Start-ServiceSafe {
    Write-Host "[INFO] Starting service..." -ForegroundColor Blue
    Stop-ConflictingProcesses
    
    $startOutput = & python ad_server_service.py start 2>&1
    Write-Host $startOutput
    
    # Always test endpoint regardless of start command result
    Start-Sleep -Seconds 3
    Test-ServiceEndpoint
}

function Stop-ServiceSafe {
    Write-Host "[INFO] Stopping service..." -ForegroundColor Blue
    & python ad_server_service.py stop
    Start-Sleep -Seconds 2
    
    # Force stop all Python processes related to our service
    Write-Host "[INFO] Stopping all related Python processes..." -ForegroundColor Blue
    Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Write-Host "  - Stopping Python PID $($_.Id)" -ForegroundColor Gray
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore errors
        }
    }
    
    Stop-ConflictingProcesses
    
    # Wait and verify all processes are stopped
    Start-Sleep -Seconds 3
    $remaining = netstat -ano | findstr "$ServicePort" | findstr "LISTENING"
    if ($remaining) {
        Write-Host "[WARNING] Some processes still listening on port $ServicePort" -ForegroundColor Yellow
        Stop-ConflictingProcesses
    } else {
        Write-Host "[SUCCESS] All processes stopped" -ForegroundColor Green
    }
}

function Test-ServiceEndpoint {
    Write-Host "[INFO] Testing service endpoint..." -ForegroundColor Blue
    
    try {
        $response = Invoke-RestMethod -Uri "http://$ServiceHost`:$ServicePort/username" -TimeoutSec 10
        Write-Host "[SUCCESS] Service is responding!" -ForegroundColor Green
        Write-Host "Username: $($response.username)" -ForegroundColor White
        Write-Host "Method: $($response.method)" -ForegroundColor Gray
        Write-Host "URL: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Cyan
        return $true
    }
    catch {
        Write-Host "[ERROR] Service endpoint not responding" -ForegroundColor Red
        Write-Host "URL: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Gray
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-ServiceStatus {
    Write-Host "[INFO] Checking service status..." -ForegroundColor Blue
    & python ad_server_service.py status
    
    # Check if port is listening
    $listening = netstat -an | findstr "$ServiceHost`:$ServicePort.*LISTENING"
    if ($listening) {
        Write-Host "[INFO] Port $ServicePort is actively listening" -ForegroundColor Green
        Test-ServiceEndpoint | Out-Null
    } else {
        Write-Host "[WARNING] Port $ServicePort is not listening" -ForegroundColor Yellow
    }
}

function Uninstall-ServiceComplete {
    Request-AdminElevation
    
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "AD Username Service - Complete Removal" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "[INFO] Starting complete service removal..." -ForegroundColor Blue
    Write-Host ""
    
    # Stop all related processes first
    Write-Host "[STEP 1] Stopping all related processes..." -ForegroundColor Yellow
    Stop-ServiceSafe
    
    # Force stop any remaining Python processes
    Write-Host "[INFO] Force stopping all Python processes..." -ForegroundColor Blue
    Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Write-Host "  - Force stopping Python PID $($_.Id)" -ForegroundColor Gray
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore errors
        }
    }
    
    # Stop Windows service if exists
    Write-Host "[STEP 2] Removing Windows service..." -ForegroundColor Yellow
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host "[INFO] Found Windows service '$ServiceName'" -ForegroundColor Blue
            
            # Stop service if running
            if ($service.Status -eq 'Running') {
                Write-Host "[INFO] Stopping Windows service..." -ForegroundColor Blue
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            }
            
            # Uninstall using Python service script
            Write-Host "[INFO] Uninstalling service via Python script..." -ForegroundColor Blue
            & python ad_server_service.py uninstall 2>&1 | Out-Host
            Start-Sleep -Seconds 2
            
            # Verify service is removed
            $serviceCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($serviceCheck) {
                Write-Host "[WARNING] Service still exists, trying manual removal..." -ForegroundColor Yellow
                try {
                    # Try to delete service manually using sc command
                    & sc.exe delete $ServiceName 2>&1 | Out-Host
                    Start-Sleep -Seconds 2
                } catch {
                    Write-Host "[WARNING] Manual service deletion failed" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[SUCCESS] Windows service removed successfully" -ForegroundColor Green
            }
        } else {
            Write-Host "[INFO] No Windows service found to remove" -ForegroundColor Gray
        }
    } catch {
        Write-Host "[WARNING] Error during service removal: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Clean up registry entries (if any)
    Write-Host "[STEP 3] Cleaning up registry entries..." -ForegroundColor Yellow
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path $regPath) {
            Write-Host "[INFO] Removing registry entries at $regPath" -ForegroundColor Blue
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[SUCCESS] Registry entries cleaned" -ForegroundColor Green
        } else {
            Write-Host "[INFO] No registry entries found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "[WARNING] Could not clean registry: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Kill any remaining processes on the port
    Write-Host "[STEP 4] Final process cleanup..." -ForegroundColor Yellow
    Stop-ConflictingProcesses
    
    # Clean up any log files or temporary files
    Write-Host "[STEP 5] Cleaning up files..." -ForegroundColor Yellow
    $filesToClean = @(
        "service.log",
        "elevated-run.log", 
        "sys-run.log",
        "*.pyc"
    )
    
    foreach ($filePattern in $filesToClean) {
        $files = Get-ChildItem -Path $scriptDir -Name $filePattern -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                $fullPath = Join-Path $scriptDir $file
                Remove-Item -Path $fullPath -Force -ErrorAction SilentlyContinue
                Write-Host "  - Removed: $file" -ForegroundColor Gray
            } catch {
                Write-Host "  - Could not remove: $file" -ForegroundColor Yellow
            }
        }
    }
    
    # Final verification
    Write-Host "[STEP 6] Final verification..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    
    $finalServiceCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $finalPortCheck = netstat -an | findstr "$ServiceHost`:$ServicePort.*LISTENING"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "REMOVAL SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    if (-not $finalServiceCheck) {
        Write-Host "[✓] Windows service removed" -ForegroundColor Green
    } else {
        Write-Host "[✗] Windows service still exists" -ForegroundColor Red
    }
    
    if (-not $finalPortCheck) {
        Write-Host "[✓] Port $ServicePort is free" -ForegroundColor Green
    } else {
        Write-Host "[✗] Port $ServicePort still in use" -ForegroundColor Red
    }
    
    Write-Host "[✓] Process cleanup completed" -ForegroundColor Green
    Write-Host "[✓] File cleanup completed" -ForegroundColor Green
    Write-Host "[✓] Registry cleanup completed" -ForegroundColor Green
    
    Write-Host ""
    if (-not $finalServiceCheck -and -not $finalPortCheck) {
        Write-Host "[SUCCESS] Complete removal finished! 🎉" -ForegroundColor Green
        Write-Host "All service components have been removed." -ForegroundColor White
    } else {
        Write-Host "[WARNING] Removal completed with some issues" -ForegroundColor Yellow
        Write-Host "You may need to restart Windows to complete the removal." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "To reinstall the service, run:" -ForegroundColor Cyan
    Write-Host "  .\install_service.ps1 install" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
}

function Start-SimpleServer {
    Write-Host "[INFO] Starting simple AD server (no Windows Service)..." -ForegroundColor Blue
    Stop-ConflictingProcesses
    
    Write-Host "[INFO] Server will run in foreground. Press Ctrl+C to stop." -ForegroundColor Yellow
    Write-Host "[INFO] Endpoint: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        & python ad_server.py
    }
    catch {
        Write-Host "[ERROR] Failed to start simple server: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-Help {
    Write-Host "AD Username Service - Installer and Manager" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\install_service.ps1 [action]" -ForegroundColor White
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Yellow
    Write-Host "  install     - Install and start Windows service (requires Admin)" -ForegroundColor Green
    Write-Host "  uninstall   - Completely remove Windows service (requires Admin)" -ForegroundColor Red
    Write-Host "  clean       - Force cleanup all service components (requires Admin)" -ForegroundColor Red
    Write-Host "  simple      - Run simple server (no Windows service)" -ForegroundColor Gray
    Write-Host "  background  - Start server in background (silent)" -ForegroundColor Gray
    Write-Host "  start       - Start the Windows service" -ForegroundColor Gray
    Write-Host "  stop        - Stop the service" -ForegroundColor Gray
    Write-Host "  restart     - Restart the service" -ForegroundColor Gray
    Write-Host "  status      - Check service status" -ForegroundColor Gray
    Write-Host "  test        - Test service endpoint" -ForegroundColor Gray
    Write-Host "  help        - Show this help" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\install_service.ps1 install    # Install Windows service (recommended)" -ForegroundColor Green
    Write-Host "  .\install_service.ps1 uninstall  # Completely remove service" -ForegroundColor Red
    Write-Host "  .\install_service.ps1 clean      # Force cleanup everything" -ForegroundColor Red
    Write-Host "  .\install_service.ps1 simple     # Run simple server (foreground)" -ForegroundColor Gray
    Write-Host "  .\install_service.ps1 status     # Check if running" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Service Endpoint: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Cyan
}

# Main execution
switch ($Action) {
    "install" { Install-ServiceComplete }
    "simple" { Start-SimpleServer }
    "start" { Start-ServiceSafe }
    "stop" { Stop-ServiceSafe }
    "restart" { 
        Stop-ServiceSafe
        Start-Sleep -Seconds 3
        Start-ServiceSafe
    }
    "status" { Get-ServiceStatus }
    "test" { Test-ServiceEndpoint }
    "background" {
        Write-Host "[INFO] Starting AD server in background (silent)..." -ForegroundColor Blue
        Stop-ConflictingProcesses
        
        # Start the server silently using VBScript
        $vbsPath = Join-Path $scriptDir "start-service-silent.vbs"
        if (Test-Path $vbsPath) {
            Start-Process "wscript.exe" -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
            Start-Sleep -Seconds 3
            
            # Test if it started
            if (Test-ServiceEndpoint) {
                Write-Host "[SUCCESS] Service started in background!" -ForegroundColor Green
                Write-Host "Service is running at: http://$ServiceHost`:$ServicePort/username" -ForegroundColor Cyan
                Write-Host "Use 'stop' to stop the background service." -ForegroundColor Yellow
            } else {
                Write-Host "[ERROR] Failed to start background service" -ForegroundColor Red
            }
        } else {
            Write-Host "[ERROR] start-service-silent.vbs not found" -ForegroundColor Red
        }
    }
    "uninstall" { Uninstall-ServiceComplete }
    "clean" { Uninstall-ServiceComplete }
    "help" { Show-Help }
    default { Show-Help }
}
