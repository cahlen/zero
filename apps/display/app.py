"""
Zero Display Application
Pygame-based framebuffer display for Raspberry Pi Zero W
"""

import os
import sys
import time
import subprocess
import threading
from datetime import datetime

# Set SDL to use framebuffer before importing pygame
os.environ['SDL_VIDEODRIVER'] = 'fbcon'
os.environ['SDL_FBDEV'] = '/dev/fb0'

import pygame
from dotenv import load_dotenv

# Load environment variables
load_dotenv('/etc/zero/secrets.env')

# Display settings
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240
FPS = 30

# Colors
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
CYAN = (0, 217, 255)
GREEN = (0, 255, 136)
GRAY = (100, 100, 100)
DARK_GRAY = (30, 30, 40)


class SystemMonitor:
    """Collects system information"""
    
    def __init__(self):
        self.data = {}
        self.update()
    
    def update(self):
        """Update system data"""
        try:
            # Temperature
            try:
                result = subprocess.check_output(['vcgencmd', 'measure_temp']).decode()
                self.data['temp'] = result.replace('temp=', '').replace("'C", '°C').strip()
            except:
                self.data['temp'] = 'N/A'
            
            # CPU usage
            with open('/proc/stat', 'r') as f:
                line = f.readline()
                values = line.split()[1:5]
                idle = int(values[3])
                total = sum(int(v) for v in values)
                if hasattr(self, '_last_idle'):
                    idle_diff = idle - self._last_idle
                    total_diff = total - self._last_total
                    self.data['cpu'] = 100 - int(100 * idle_diff / total_diff) if total_diff > 0 else 0
                else:
                    self.data['cpu'] = 0
                self._last_idle = idle
                self._last_total = total
            
            # Memory
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
                total = int([l for l in meminfo.split('\n') if 'MemTotal' in l][0].split()[1])
                available = int([l for l in meminfo.split('\n') if 'MemAvailable' in l][0].split()[1])
                self.data['mem'] = int((1 - available / total) * 100)
            
            # WiFi status
            try:
                result = subprocess.run(
                    ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
                    capture_output=True, text=True, timeout=5
                )
                wifi_name = None
                for line in result.stdout.strip().split('\n'):
                    parts = line.split(':')
                    if len(parts) >= 2 and parts[1] == '802-11-wireless':
                        wifi_name = parts[0]
                        break
                self.data['wifi'] = wifi_name or 'Not connected'
            except:
                self.data['wifi'] = 'Error'
            
            # IP Address
            try:
                result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
                ip = result.stdout.strip().split()[0] if result.stdout.strip() else 'N/A'
                self.data['ip'] = ip
            except:
                self.data['ip'] = 'N/A'
                
        except Exception as e:
            print(f"Error updating system data: {e}")


class ZeroDisplay:
    """Main display application"""
    
    def __init__(self):
        pygame.init()
        pygame.mouse.set_visible(False)
        
        # Try to set display mode
        try:
            self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        except pygame.error:
            # Fallback for development
            os.environ['SDL_VIDEODRIVER'] = 'x11'
            self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        
        pygame.display.set_caption('Zero')
        self.clock = pygame.time.Clock()
        
        # Load fonts
        pygame.font.init()
        self.font_large = pygame.font.Font(None, 48)
        self.font_medium = pygame.font.Font(None, 28)
        self.font_small = pygame.font.Font(None, 20)
        
        # System monitor
        self.monitor = SystemMonitor()
        self.last_update = time.time()
        
        # Screen state
        self.current_screen = 'status'
        self.running = True
    
    def draw_status_screen(self):
        """Draw main status screen"""
        self.screen.fill(DARK_GRAY)
        
        # Header
        time_str = datetime.now().strftime('%H:%M')
        time_surface = self.font_large.render(time_str, True, CYAN)
        self.screen.blit(time_surface, (SCREEN_WIDTH // 2 - time_surface.get_width() // 2, 10))
        
        date_str = datetime.now().strftime('%a %b %d')
        date_surface = self.font_small.render(date_str, True, GRAY)
        self.screen.blit(date_surface, (SCREEN_WIDTH // 2 - date_surface.get_width() // 2, 55))
        
        # Divider
        pygame.draw.line(self.screen, GRAY, (20, 80), (SCREEN_WIDTH - 20, 80), 1)
        
        # Status items
        y = 95
        items = [
            ('WiFi', self.monitor.data.get('wifi', 'N/A'), GREEN if self.monitor.data.get('wifi') != 'Not connected' else GRAY),
            ('IP', self.monitor.data.get('ip', 'N/A'), WHITE),
            ('CPU', f"{self.monitor.data.get('cpu', 0)}%", WHITE),
            ('Memory', f"{self.monitor.data.get('mem', 0)}%", WHITE),
            ('Temp', self.monitor.data.get('temp', 'N/A'), WHITE),
        ]
        
        for label, value, color in items:
            # Label
            label_surface = self.font_small.render(label, True, GRAY)
            self.screen.blit(label_surface, (20, y))
            
            # Value
            value_surface = self.font_small.render(value, True, color)
            self.screen.blit(value_surface, (SCREEN_WIDTH - 20 - value_surface.get_width(), y))
            
            y += 28
        
        # Footer
        pygame.draw.line(self.screen, GRAY, (20, SCREEN_HEIGHT - 30), (SCREEN_WIDTH - 20, SCREEN_HEIGHT - 30), 1)
        footer = self.font_small.render('⚡ Zero', True, CYAN)
        self.screen.blit(footer, (SCREEN_WIDTH // 2 - footer.get_width() // 2, SCREEN_HEIGHT - 22))
    
    def draw_progress_bar(self, x, y, width, height, value, max_value, color):
        """Draw a progress bar"""
        # Background
        pygame.draw.rect(self.screen, GRAY, (x, y, width, height), border_radius=3)
        
        # Fill
        fill_width = int((value / max_value) * width)
        if fill_width > 0:
            pygame.draw.rect(self.screen, color, (x, y, fill_width, height), border_radius=3)
    
    def handle_events(self):
        """Handle pygame events"""
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    self.running = False
                elif event.key == pygame.K_SPACE:
                    # Cycle screens
                    pass
    
    def run(self):
        """Main loop"""
        print("Zero Display starting...")
        
        while self.running:
            self.handle_events()
            
            # Update system data every 2 seconds
            if time.time() - self.last_update > 2:
                self.monitor.update()
                self.last_update = time.time()
            
            # Draw current screen
            if self.current_screen == 'status':
                self.draw_status_screen()
            
            pygame.display.flip()
            self.clock.tick(FPS)
        
        pygame.quit()


def main():
    """Entry point"""
    try:
        app = ZeroDisplay()
        app.run()
    except Exception as e:
        print(f"Display error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
