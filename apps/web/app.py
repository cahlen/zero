"""
Zero Web Application
Main web server for device features and settings
"""

import os
import subprocess
import json
from functools import wraps
from flask import Flask, render_template, request, jsonify, redirect, url_for
from dotenv import load_dotenv

# Load environment variables
load_dotenv('/etc/zero/secrets.env')

app = Flask(__name__)
app.secret_key = os.urandom(24)

CONFIG_DIR = "/etc/zero"
SECRETS_FILE = f"{CONFIG_DIR}/secrets.env"

# AI Provider configurations
AI_PROVIDERS = {
    "openai": {"name": "OpenAI", "env_var": "OPENAI_API_KEY"},
    "anthropic": {"name": "Anthropic (Claude)", "env_var": "ANTHROPIC_API_KEY"},
    "google": {"name": "Google (Gemini)", "env_var": "GOOGLE_API_KEY"},
    "groq": {"name": "Groq", "env_var": "GROQ_API_KEY"},
    "xai": {"name": "xAI (Grok)", "env_var": "XAI_API_KEY"}
}


def get_system_info():
    """Get system information"""
    info = {}
    
    try:
        # Hostname
        info['hostname'] = subprocess.check_output(['hostname']).decode().strip()
        
        # IP Address
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
        info['ip'] = result.stdout.strip().split()[0] if result.stdout.strip() else 'N/A'
        
        # Uptime
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
            hours = int(uptime_seconds // 3600)
            minutes = int((uptime_seconds % 3600) // 60)
            info['uptime'] = f"{hours}h {minutes}m"
        
        # Temperature
        try:
            temp = subprocess.check_output(['vcgencmd', 'measure_temp']).decode()
            info['temperature'] = temp.replace('temp=', '').strip()
        except:
            info['temperature'] = 'N/A'
        
        # Memory
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()
            total = int([l for l in meminfo.split('\n') if 'MemTotal' in l][0].split()[1])
            available = int([l for l in meminfo.split('\n') if 'MemAvailable' in l][0].split()[1])
            used_percent = int((1 - available / total) * 100)
            info['memory'] = f"{used_percent}% used"
        
        # Disk
        result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
        lines = result.stdout.strip().split('\n')
        if len(lines) > 1:
            parts = lines[1].split()
            info['disk'] = f"{parts[4]} used ({parts[2]} / {parts[1]})"
        
        # WiFi
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
            capture_output=True, text=True
        )
        for line in result.stdout.strip().split('\n'):
            parts = line.split(':')
            if len(parts) >= 2 and parts[1] == '802-11-wireless':
                info['wifi'] = parts[0]
                break
        else:
            info['wifi'] = 'Not connected'
            
    except Exception as e:
        print(f"Error getting system info: {e}")
    
    return info


def get_configured_providers():
    """Get list of AI providers with keys configured"""
    configured = []
    for provider_id, provider in AI_PROVIDERS.items():
        key = os.environ.get(provider['env_var'], '')
        if key:
            configured.append({
                'id': provider_id,
                'name': provider['name'],
                'configured': True,
                'key_preview': key[:8] + '...' if len(key) > 8 else '***'
            })
        else:
            configured.append({
                'id': provider_id,
                'name': provider['name'],
                'configured': False,
                'key_preview': None
            })
    return configured


@app.route('/')
def index():
    """Dashboard"""
    system_info = get_system_info()
    providers = get_configured_providers()
    
    return render_template('index.html',
                         system_info=system_info,
                         providers=providers)


@app.route('/settings')
def settings():
    """Settings page"""
    providers = get_configured_providers()
    return render_template('settings.html', providers=providers)


@app.route('/settings/api-keys', methods=['POST'])
def update_api_keys():
    """Update AI API keys"""
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
        for provider_id, provider in AI_PROVIDERS.items():
            key = request.form.get(provider_id, '').strip()
            if key:
                existing[provider['env_var']] = key
            elif request.form.get(f'{provider_id}_clear'):
                existing.pop(provider['env_var'], None)
        
        # Write back
        with open(SECRETS_FILE, 'w') as f:
            f.write("# Zero - AI API Keys Configuration\n")
            f.write("# Updated via Web Interface\n\n")
            for key, value in existing.items():
                f.write(f"{key}={value}\n")
        
        os.chmod(SECRETS_FILE, 0o600)
        
        # Reload environment
        load_dotenv(SECRETS_FILE, override=True)
        
        return jsonify({"success": True, "message": "API keys updated"})
    
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})


@app.route('/api/status')
def api_status():
    """API endpoint for system status"""
    return jsonify(get_system_info())


@app.route('/api/ai/test/<provider>')
def test_ai_provider(provider):
    """Test an AI provider connection"""
    if provider not in AI_PROVIDERS:
        return jsonify({"success": False, "message": "Unknown provider"})
    
    env_var = AI_PROVIDERS[provider]['env_var']
    api_key = os.environ.get(env_var)
    
    if not api_key:
        return jsonify({"success": False, "message": "No API key configured"})
    
    # Simple connectivity test based on provider
    # In production, you'd make actual API calls
    return jsonify({
        "success": True,
        "message": f"API key configured for {AI_PROVIDERS[provider]['name']}"
    })


@app.route('/system/reboot', methods=['POST'])
def system_reboot():
    """Reboot the system"""
    subprocess.Popen(['reboot'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return jsonify({"success": True, "message": "Rebooting..."})


@app.route('/system/shutdown', methods=['POST'])
def system_shutdown():
    """Shutdown the system"""
    subprocess.Popen(['shutdown', '-h', 'now'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return jsonify({"success": True, "message": "Shutting down..."})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
