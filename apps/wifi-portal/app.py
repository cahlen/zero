"""
Zero WiFi Configuration Portal
Captive portal for initial WiFi setup on Raspberry Pi Zero W
"""

import os
import subprocess
import json
from flask import Flask, render_template, request, redirect, jsonify, url_for

app = Flask(__name__)

WIFI_INTERFACE = "wlan0"
CONFIG_DIR = "/etc/zero"
SECRETS_FILE = f"{CONFIG_DIR}/secrets.env"

# AI Provider configurations
AI_PROVIDERS = {
    "openai": {
        "name": "OpenAI",
        "env_var": "OPENAI_API_KEY",
        "url": "https://platform.openai.com/api-keys",
        "prefix": "sk-"
    },
    "anthropic": {
        "name": "Anthropic (Claude)",
        "env_var": "ANTHROPIC_API_KEY",
        "url": "https://console.anthropic.com/",
        "prefix": "sk-ant-"
    },
    "google": {
        "name": "Google (Gemini)",
        "env_var": "GOOGLE_API_KEY",
        "url": "https://makersuite.google.com/app/apikey",
        "prefix": "AI"
    },
    "groq": {
        "name": "Groq",
        "env_var": "GROQ_API_KEY",
        "url": "https://console.groq.com/keys",
        "prefix": "gsk_"
    },
    "xai": {
        "name": "xAI (Grok)",
        "env_var": "XAI_API_KEY",
        "url": "https://console.x.ai/",
        "prefix": "xai-"
    }
}


def get_wifi_networks():
    """Scan for available WiFi networks"""
    try:
        result = subprocess.run(
            ["nmcli", "--colors", "no", "-m", "multiline", 
             "--get-value", "SSID,SIGNAL,SECURITY", 
             "dev", "wifi", "list", "ifname", WIFI_INTERFACE],
            capture_output=True, text=True, timeout=30
        )
        
        networks = []
        lines = result.stdout.strip().split('\n')
        
        # Parse multiline output (SSID, SIGNAL, SECURITY per network)
        i = 0
        while i < len(lines) - 2:
            ssid = lines[i].strip()
            signal = lines[i + 1].strip()
            security = lines[i + 2].strip()
            
            if ssid and ssid != "--" and not ssid.startswith("Zero-Setup"):
                networks.append({
                    "ssid": ssid,
                    "signal": int(signal) if signal.isdigit() else 0,
                    "security": security
                })
            i += 3
        
        # Sort by signal strength
        networks.sort(key=lambda x: x["signal"], reverse=True)
        
        # Remove duplicates
        seen = set()
        unique_networks = []
        for n in networks:
            if n["ssid"] not in seen:
                seen.add(n["ssid"])
                unique_networks.append(n)
        
        return unique_networks
    
    except Exception as e:
        print(f"Error scanning networks: {e}")
        return []


def connect_to_wifi(ssid, password):
    """Connect to a WiFi network"""
    try:
        # Try to connect
        result = subprocess.run(
            ["nmcli", "device", "wifi", "connect", ssid,
             "ifname", WIFI_INTERFACE, "password", password],
            capture_output=True, text=True, timeout=60
        )
        
        if result.returncode == 0:
            return True, "Connected successfully"
        else:
            return False, result.stderr or "Connection failed"
    
    except subprocess.TimeoutExpired:
        return False, "Connection timed out"
    except Exception as e:
        return False, str(e)


def get_current_connection():
    """Get current WiFi connection status"""
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show", "--active"],
            capture_output=True, text=True
        )
        
        for line in result.stdout.strip().split('\n'):
            parts = line.split(':')
            if len(parts) >= 3 and parts[1] == "802-11-wireless":
                return parts[0]
        
        return None
    except Exception:
        return None


def get_ip_address():
    """Get current IP address"""
    try:
        result = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", WIFI_INTERFACE],
            capture_output=True, text=True
        )
        if result.stdout:
            # Parse: "3: wlan0    inet 192.168.0.12/24..."
            parts = result.stdout.split()
            for i, part in enumerate(parts):
                if part == "inet" and i + 1 < len(parts):
                    return parts[i + 1].split('/')[0]
        return None
    except Exception:
        return None


def save_api_keys(keys):
    """Save API keys to secrets file"""
    try:
        # Read existing secrets
        existing = {}
        if os.path.exists(SECRETS_FILE):
            with open(SECRETS_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        existing[key] = value
        
        # Update with new keys
        for provider_id, api_key in keys.items():
            if api_key and provider_id in AI_PROVIDERS:
                env_var = AI_PROVIDERS[provider_id]["env_var"]
                existing[env_var] = api_key
        
        # Write back
        with open(SECRETS_FILE, 'w') as f:
            f.write("# Zero - AI API Keys Configuration\n")
            f.write("# Auto-generated by WiFi Portal\n\n")
            for key, value in existing.items():
                f.write(f"{key}={value}\n")
        
        os.chmod(SECRETS_FILE, 0o600)
        return True
    
    except Exception as e:
        print(f"Error saving API keys: {e}")
        return False


def mark_wifi_configured():
    """Mark WiFi as configured to switch from AP mode"""
    try:
        # Create marker file
        open(f"{CONFIG_DIR}/.wifi_configured", 'w').close()
        
        # Disable the hotspot after a delay
        subprocess.Popen(
            ["bash", "-c", "sleep 10 && nmcli connection down 'Zero-Setup-*' 2>/dev/null || true"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        
        return True
    except Exception:
        return False


@app.route('/')
def index():
    """Main setup page"""
    networks = get_wifi_networks()
    current = get_current_connection()
    ip = get_ip_address()
    
    return render_template('index.html', 
                         networks=networks,
                         current_connection=current,
                         ip_address=ip,
                         ai_providers=AI_PROVIDERS)


@app.route('/scan')
def scan():
    """Rescan WiFi networks"""
    networks = get_wifi_networks()
    return jsonify(networks)


@app.route('/connect', methods=['POST'])
def connect():
    """Connect to selected WiFi network"""
    ssid = request.form.get('ssid')
    password = request.form.get('password', '')
    
    if not ssid:
        return jsonify({"success": False, "message": "No network selected"})
    
    success, message = connect_to_wifi(ssid, password)
    
    if success:
        mark_wifi_configured()
    
    return jsonify({"success": success, "message": message})


@app.route('/api-keys', methods=['POST'])
def save_keys():
    """Save AI API keys"""
    keys = {}
    for provider_id in AI_PROVIDERS:
        key = request.form.get(provider_id)
        if key:
            keys[provider_id] = key.strip()
    
    if save_api_keys(keys):
        return jsonify({"success": True, "message": "API keys saved"})
    else:
        return jsonify({"success": False, "message": "Failed to save keys"})


@app.route('/status')
def status():
    """Get current connection status"""
    current = get_current_connection()
    ip = get_ip_address()
    
    return jsonify({
        "connected": current is not None and not current.startswith("Zero-Setup"),
        "network": current,
        "ip": ip
    })


@app.route('/reboot', methods=['POST'])
def reboot():
    """Reboot the device"""
    subprocess.Popen(["reboot"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return jsonify({"success": True, "message": "Rebooting..."})


# Captive portal detection endpoints
@app.route('/generate_204')
@app.route('/gen_204')
@app.route('/hotspot-detect.html')
@app.route('/library/test/success.html')
@app.route('/ncsi.txt')
@app.route('/connecttest.txt')
@app.route('/redirect')
def captive_portal_detect():
    """Redirect captive portal detection to main page"""
    return redirect(url_for('index'))


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
