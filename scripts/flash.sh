#!/bin/bash
# Zero - WiFi Provisioning Flash Script
# 
# Flashes a Raspberry Pi Zero W with a captive portal that allows
# users to configure WiFi credentials on first boot.
#
# Usage: sudo bash flash.sh /dev/sdX
#
# What this does:
#   1. Flashes Raspberry Pi OS Bullseye to SD card
#   2. Configures hotspot (SSID: Zero-Setup, open network)
#   3. Sets up captive portal with WiFi network selection
#   4. Includes brcmfmac workarounds to prevent kernel crashes
#
# After boot:
#   - Connect to "Zero-Setup" WiFi
#   - Captive portal opens automatically  
#   - Select your home network and enter password
#   - Pi reboots and joins your network
#
# SSH: pi / zero

set -e

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

IMAGE_RAW="/tmp/bullseye.img"

if [ ! -f "$IMAGE_RAW" ]; then
    echo "Bullseye image not found"
    exit 1
fi

echo "Flashing..."
sudo dd if="$IMAGE_RAW" of="$DEVICE" bs=4M status=progress conv=fsync
sync
sleep 2
sudo partprobe "$DEVICE"
sleep 2

BOOT="${DEVICE}1"
ROOT="${DEVICE}2"

sudo mkdir -p /mnt/piboot /mnt/piroot
sudo mount "$BOOT" /mnt/piboot
sudo mount "$ROOT" /mnt/piroot

# Enable SSH
sudo touch /mnt/piboot/ssh

# Set pi password
sudo chroot /mnt/piroot /bin/bash -c "echo 'pi:zero' | chpasswd"

# Disable Bluetooth
echo "dtoverlay=disable-bt" | sudo tee -a /mnt/piboot/config.txt

# Install packages
echo "Installing packages..."
sudo cp /usr/bin/qemu-arm-static /mnt/piroot/usr/bin/ 2>/dev/null || true
sudo mount --bind /dev /mnt/piroot/dev
sudo mount --bind /proc /mnt/piroot/proc
sudo mount --bind /sys /mnt/piroot/sys
sudo cp /etc/resolv.conf /mnt/piroot/etc/resolv.conf

sudo chroot /mnt/piroot /bin/bash << 'CHROOT'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
apt-get update
apt-get install -y hostapd dnsmasq lighttpd php-cgi
systemctl unmask hostapd
systemctl enable hostapd dnsmasq lighttpd
lighty-enable-mod fastcgi-php 2>/dev/null || true
CHROOT

sudo umount /mnt/piroot/dev /mnt/piroot/proc /mnt/piroot/sys

# brcmfmac workarounds
sudo tee /mnt/piroot/etc/modprobe.d/brcmfmac.conf > /dev/null << 'EOF'
options brcmfmac roamoff=1 feature_disable=0x282000
EOF

# WiFi scan script
sudo tee /mnt/piroot/usr/local/bin/wifi-scan.sh > /dev/null << 'EOF'
#!/bin/bash
SCAN_FILE="/var/www/html/networks.json"
for i in {1..10}; do
    ip link show wlan0 &>/dev/null && break
    sleep 1
done
ip link set wlan0 up
sleep 2
networks="["
first=true
while IFS= read -r line; do
    if [[ "$line" =~ ESSID:\"(.+)\" ]]; then
        ssid="${BASH_REMATCH[1]}"
        if [ -n "$ssid" ]; then
            [ "$first" = true ] && first=false || networks+=","
            networks+="{\"ssid\":\"$ssid\",\"quality\":${quality:-50}}"
        fi
    elif [[ "$line" =~ Quality=([0-9]+) ]]; then
        quality="${BASH_REMATCH[1]}"
    fi
done < <(iwlist wlan0 scan 2>/dev/null)
networks+="]"
mkdir -p /var/www/html
echo "$networks" > "$SCAN_FILE"
chmod 644 "$SCAN_FILE"
EOF
sudo chmod +x /mnt/piroot/usr/local/bin/wifi-scan.sh

# WiFi connect script
sudo tee /mnt/piroot/usr/local/bin/wifi-connect.sh > /dev/null << 'EOF'
#!/bin/bash
SSID="$1"
PASS="$2"

cat > /etc/wpa_supplicant/wpa_supplicant.conf << WPAEOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$PASS"
    key_mgmt=WPA-PSK
}
WPAEOF

systemctl disable hostapd
systemctl disable dnsmasq  
systemctl disable wifi-scan

sed -i '/interface wlan0/,/nohook wpa_supplicant/d' /etc/dhcpcd.conf

touch /etc/wifi-configured
sync
reboot
EOF
sudo chmod +x /mnt/piroot/usr/local/bin/wifi-connect.sh

# Allow www-data to run wifi-connect script
sudo tee /mnt/piroot/etc/sudoers.d/wifi-connect > /dev/null << 'EOF'
www-data ALL=(ALL) NOPASSWD: /usr/local/bin/wifi-connect.sh
EOF
sudo chmod 440 /mnt/piroot/etc/sudoers.d/wifi-connect

# Systemd service for wifi scan
sudo tee /mnt/piroot/etc/systemd/system/wifi-scan.service > /dev/null << 'EOF'
[Unit]
Description=Scan WiFi networks before AP mode
Before=hostapd.service
After=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-scan.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo chroot /mnt/piroot systemctl enable wifi-scan.service

# hostapd config
sudo mkdir -p /mnt/piroot/etc/hostapd
sudo tee /mnt/piroot/etc/hostapd/hostapd.conf > /dev/null << 'EOF'
interface=wlan0
driver=nl80211
ssid=Zero-Setup
hw_mode=g
channel=6
auth_algs=1
wmm_enabled=0
EOF

sudo tee /mnt/piroot/etc/default/hostapd > /dev/null << 'EOF'
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

# dnsmasq
sudo tee /mnt/piroot/etc/dnsmasq.conf > /dev/null << 'EOF'
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
address=/#/192.168.4.1
EOF

# Static IP for AP mode
sudo tee -a /mnt/piroot/etc/dhcpcd.conf > /dev/null << 'EOF'

interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

# Simple captive portal - no JavaScript needed for form submission
sudo mkdir -p /mnt/piroot/var/www/html
sudo tee /mnt/piroot/var/www/html/index.php > /dev/null << 'PHPEOF'
<?php
$networks = [];
$scan_file = '/var/www/html/networks.json';
if (file_exists($scan_file)) {
    $data = json_decode(file_get_contents($scan_file), true);
    if (is_array($data)) {
        foreach ($data as $net) {
            if (!empty($net['ssid'])) $networks[$net['ssid']] = $net['quality'] ?? 50;
        }
        arsort($networks);
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>ZERO SETUP</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: 'Courier New', monospace;
            background: #0a0a0a; color: #00ff41;
            min-height: 100vh; padding: 20px;
        }
        .container { max-width: 500px; margin: 0 auto; }
        h1 { text-align: center; font-size: 28px; margin-bottom: 10px; text-shadow: 0 0 10px #00ff41; }
        .subtitle { text-align: center; color: #ffb000; margin-bottom: 30px; }
        .terminal {
            background: #0d1117; border: 2px solid #00ff41;
            padding: 20px; border-radius: 4px;
        }
        label { display: block; color: #ffb000; font-size: 14px; margin: 15px 0 8px; }
        select, input[type="text"], input[type="password"] {
            width: 100%; padding: 15px; background: #000; border: 2px solid #00ff41;
            color: #00ff41; font-family: 'Courier New', monospace; font-size: 16px;
            border-radius: 4px; -webkit-appearance: none; appearance: none;
        }
        select { background: #000 url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><path fill="%2300ff41" d="M6 9L1 4h10z"/></svg>') no-repeat right 15px center; }
        select option { background: #000; color: #00ff41; padding: 10px; }
        input:focus, select:focus { outline: none; border-color: #ffb000; box-shadow: 0 0 10px #00ff41; }
        button {
            width: 100%; padding: 18px; margin-top: 25px;
            background: #00ff41; border: none; color: #000;
            font-family: 'Courier New', monospace; font-size: 18px; font-weight: bold;
            cursor: pointer; border-radius: 4px;
        }
        button:active { background: #00cc33; }
        .or { text-align: center; color: #666; margin: 15px 0; }
        .info { margin-top: 20px; padding: 15px; background: #1a1a1a; border-radius: 4px; font-size: 12px; color: #666; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>// ZERO SETUP</h1>
        <div class="subtitle">[ NETWORK ACCESS ]</div>
        
        <div class="terminal">
            <form action="/connect.php" method="POST">
                
                <?php if (count($networks) > 0): ?>
                <label>SELECT NETWORK:</label>
                <select name="ssid">
                    <option value="">-- Choose WiFi --</option>
                    <?php foreach ($networks as $ssid => $quality): ?>
                    <option value="<?php echo htmlspecialchars($ssid); ?>"><?php echo htmlspecialchars($ssid); ?></option>
                    <?php endforeach; ?>
                </select>
                
                <div class="or">- OR -</div>
                <?php endif; ?>
                
                <label>ENTER NETWORK NAME:</label>
                <input type="text" name="manual_ssid" placeholder="WiFi name (SSID)">
                
                <label>PASSWORD:</label>
                <input type="password" name="password" placeholder="WiFi password" required>
                
                <button type="submit">CONNECT</button>
            </form>
            
            <div class="info">
                Device will reboot and connect to your network.<br>
                This hotspot will disappear.
            </div>
        </div>
    </div>
</body>
</html>
PHPEOF

# PHP connect handler
sudo tee /mnt/piroot/var/www/html/connect.php > /dev/null << 'PHPEOF'
<?php
$ssid = trim($_POST['ssid'] ?? '');
$manual = trim($_POST['manual_ssid'] ?? '');
$password = $_POST['password'] ?? '';

// Use manual entry if provided, otherwise use dropdown
if (!empty($manual)) {
    $ssid = $manual;
}

if (empty($ssid) || empty($password)) {
    echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width"><style>body{font-family:monospace;background:#0a0a0a;color:#ff0040;padding:40px;text-align:center;}a{color:#00ff41;}</style></head><body>';
    echo '<h1>ERROR</h1><p>Network name and password required</p><br><a href="/">[ GO BACK ]</a></body></html>';
    exit;
}

// Escape for shell
$ssid_escaped = escapeshellarg($ssid);
$pass_escaped = escapeshellarg($password);

// Run connect script
$cmd = "sudo /usr/local/bin/wifi-connect.sh $ssid_escaped $pass_escaped";
exec($cmd . " > /tmp/connect.log 2>&1 &");

// Show success page
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>REBOOTING</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: 'Courier New', monospace;
            background: #0a0a0a; color: #00ff41;
            min-height: 100vh; display: flex;
            align-items: center; justify-content: center; padding: 20px;
        }
        .container {
            background: #0d1117; border: 2px solid #00ff41;
            padding: 40px; max-width: 400px; text-align: center;
            border-radius: 4px;
        }
        h1 { font-size: 28px; margin-bottom: 20px; }
        .network { color: #ffb000; font-size: 20px; margin: 20px 0; word-break: break-all; }
        .loading { font-size: 24px; letter-spacing: 3px; }
        .dot { animation: blink 1s infinite; }
        .dot:nth-child(2) { animation-delay: 0.2s; }
        .dot:nth-child(3) { animation-delay: 0.4s; }
        @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
        .info { margin-top: 30px; color: #666; font-size: 14px; line-height: 1.8; }
    </style>
</head>
<body>
    <div class="container">
        <h1>// REBOOTING</h1>
        <div class="network"><?php echo htmlspecialchars($ssid); ?></div>
        <div class="loading">
            <span class="dot">.</span><span class="dot">.</span><span class="dot">.</span>
        </div>
        <div class="info">
            WiFi configured.<br>
            System rebooting...<br><br>
            This hotspot will disappear.<br>
            Find device on your network.
        </div>
    </div>
</body>
</html>
PHPEOF

# Lighttpd config
sudo tee /mnt/piroot/etc/lighttpd/lighttpd.conf > /dev/null << 'EOF'
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_redirect",
    "mod_fastcgi"
)
server.document-root = "/var/www/html"
server.upload-dirs = ( "/var/cache/lighttpd/uploads" )
server.errorlog = "/var/log/lighttpd/error.log"
server.pid-file = "/run/lighttpd.pid"
server.port = 80
index-file.names = ( "index.php", "index.html" )
url.access-deny = ( "~", ".inc" )
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )
server.error-handler-404 = "/index.php"
fastcgi.server = ( ".php" => ((
    "bin-path" => "/usr/bin/php-cgi",
    "socket" => "/tmp/php.socket"
)))
mimetype.assign = (
    ".html" => "text/html",
    ".css" => "text/css",
    ".js" => "application/javascript"
)
EOF

sudo rm -f /mnt/piroot/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service

sudo umount /mnt/piboot /mnt/piroot
sync

echo ""
echo "=== DONE ==="
echo "SSID: Zero-Setup (OPEN)"
echo "IP: 192.168.4.1"
echo "SSH: pi / zero"
