#!/usr/bin/env python3
"""
Simple HTTP server to get AD username (sAMAccountName)
Run: python ad_server.py
Test: curl http://127.0.0.1:7777/username
"""

import json
import os
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

class ADUsernameHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        
        # Add CORS headers
        self.send_cors_headers()
        
        if parsed_path.path == '/username' or parsed_path.path == '/':
            self.get_username()
        else:
            self.send_error(404, "Not Found")
    
    def do_OPTIONS(self):
        """Handle preflight OPTIONS requests"""
        self.send_cors_headers()
        self.send_response(204)
        self.end_headers()
    
    def send_cors_headers(self):
        """Send CORS headers for browser compatibility"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Type', 'application/json; charset=utf-8')
    
    def get_username(self):
        """Get AD username and return as JSON"""
        try:
            username = self.get_ad_username()
            response = {
                "ok": True,
                "username": username,
                "method": "AD" if self.is_domain_joined() else "fallback"
            }
        except Exception as e:
            response = {
                "ok": False,
                "username": "",
                "error": str(e)
            }
        
        # Send response
        self.end_headers()
        response_json = json.dumps(response, ensure_ascii=False)
        self.wfile.write(response_json.encode('utf-8'))
    
    def get_ad_username(self):
        """Get AD username (sAMAccountName) from domain"""
        try:
            # Method 1: Try PowerShell Get-ADUser (requires RSAT)
            cmd = [
                'powershell', '-Command',
                'try { Import-Module ActiveDirectory -ErrorAction Stop; '
                '(Get-ADUser -Identity $env:USERNAME).sAMAccountName } '
                'catch { $env:USERNAME }'
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception:
            pass
        
        try:
            # Method 2: Try whoami command
            cmd = ['whoami']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                # Extract username from DOMAIN\username format
                username = result.stdout.strip()
                if '\\' in username:
                    return username.split('\\')[-1]
                return username
        except Exception:
            pass
        
        try:
            # Method 3: Try net user command
            username = os.environ.get('USERNAME', '')
            if username:
                cmd = ['net', 'user', username, '/domain']
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    return username
        except Exception:
            pass
        
        # Fallback: Environment variable
        return os.environ.get('USERNAME', 'unknown')
    
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

def main():
    """Start the HTTP server"""
    host = '127.0.0.1'
    port = 7777
    
    print(f"Starting AD Username HTTP Server...")
    print(f"Server: http://{host}:{port}/")
    print(f"Endpoint: http://{host}:{port}/username")
    print(f"Press Ctrl+C to stop")
    print("-" * 50)
    
    try:
        server = HTTPServer((host, port), ADUsernameHandler)
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped by user")
    except Exception as e:
        print(f"Server error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
