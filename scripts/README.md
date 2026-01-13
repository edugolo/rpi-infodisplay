# Raspberry Pi Kiosk Deployment

This script automates the setup of a Raspberry Pi 5 as a kiosk display.

## Prerequisites

### 1. Install Raspberry Pi OS

1. Download and install [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Flash Raspberry Pi OS (64-bit) to your SD card
3. During setup, choose your keyboard layout
4. Create a user account (e.g., `edugo`) with a password

### 2. Enable SSH on the Pi

1. Boot the Pi and log in
2. Open a terminal and run:
   ```bash
   sudo raspi-config
   ```
3. Navigate to **Interface Options** → **SSH** → **Enable**
4. Exit raspi-config

### 3. Get the Pi's IP Address

```bash
hostname -I
```

Note the IP address for the next step.

## Deployment

Run the deployment script from your PC:

```bash
./scripts/deploy_pi.sh
```

The script will prompt for:

- **Pi IP Address** - The IP noted above
- **Pi Username** - Default: `edugo`
- **Device Name** - Identifier for the device
- **Location** - Physical location of the display
- **Display URL** - URL to show in kiosk mode
- **Controller URL** - API endpoint for device registration
- **Git Repo URL** - Repository to clone

After completion, the Pi will reboot and automatically start in kiosk mode.

## What the Script Does

1. Installs system dependencies (X11, audio, graphics libraries)
2. Applies Pi 5-specific Xorg fixes
3. Installs Node.js v18 via nvm
4. Clones and sets up the kiosk application
5. Generates `config.json` and `.xinitrc`
6. Configures autologin and kiosk autostart
7. Sets up daily auto-updates via cron (6:00 AM)
