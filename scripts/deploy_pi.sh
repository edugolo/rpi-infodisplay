#!/bin/bash

# ==========================================
#  Remote Kiosk Deployer (Run this on PC)
# ==========================================

echo "--- Raspberry Pi 5 Kiosk Deployer ---"

# Detect local timezone to use as default for remote Pi
LOCAL_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Europe/Brussels")

# Main deployment loop
while true; do
    echo ""
    echo "============================================"
    echo "         Starting New Pi Deployment"
    echo "============================================"
    echo ""

    # 1. Prompt for Connection Details (Host Side)
    read -p "Enter Pi IP Address: " TARGET_IP
    read -p "Enter Pi Username [edugo]: " INPUT_USER
    TARGET_USER="${INPUT_USER:-edugo}"
    read -p "Enter Timezone [$LOCAL_TIMEZONE]: " INPUT_TIMEZONE
    TARGET_TIMEZONE="${INPUT_TIMEZONE:-$LOCAL_TIMEZONE}"

    echo "-------------------------------------"
    echo "Target: $TARGET_USER@$TARGET_IP"
    echo "-------------------------------------"

    # 2. Define the Remote Script Content
    #    This function contains the entire installer that runs ON THE PI.
    get_remote_script() {
# First, inject the timezone variable (expanded on host side)
cat <<TIMEZONE_EOF
#!/bin/bash
TARGET_TIMEZONE="$TARGET_TIMEZONE"
TIMEZONE_EOF

# Then, the rest of the script (not expanded - single quotes)
cat <<'REMOTE_EOF'

# ==========================================
#  RPI 5 Kiosk Installer (Running on Pi)
# ==========================================

# --- Step 0: User Configuration ---
echo "--- Configuration Setup ---"
echo "Press ENTER to accept default values."
echo ""

# A. Name
read -p "Enter Device Name [raspberrypi]: " INPUT_NAME
NAME="${INPUT_NAME:-raspberrypi}"

# B. Location
read -p "Enter Location [location]: " INPUT_LOCATION
LOCATION="${INPUT_LOCATION:-location}"

# C. Display URL
DEFAULT_URL="https://edugo.be"
read -p "Enter Display URL [$DEFAULT_URL]: " INPUT_URL
TARGET_URL="${INPUT_URL:-$DEFAULT_URL}"

# D. Controller URL (New Prompt)
DEFAULT_CONTROLLER="https://app.edugo.be/api/v1/devices/register"
read -p "Enter Controller URL [$DEFAULT_CONTROLLER]: " INPUT_CONTROLLER
CONTROLLER_URL="${INPUT_CONTROLLER:-$DEFAULT_CONTROLLER}"

# E. Git Repository URL
DEFAULT_REPO="https://github.com/edugolo/rpi-infodisplay.git"
read -p "Enter Git Repo URL [$DEFAULT_REPO]: " INPUT_REPO
REPO_URL="${INPUT_REPO:-$DEFAULT_REPO}"

USER_HOME="/home/$USER"
REPO_DIR="$USER_HOME/rpi-infodisplay"

echo ""
echo "--- Starting Install for: $NAME ---"
sleep 2

# --- Step 1: System Updates & Fixes ---
echo "[1/8] Installing System Dependencies..."
sudo apt-get update
sudo apt-get upgrade -y

sudo apt-get install -y \
    git snmpd snmp pulseaudio libgtk-3-0 upower \
    xinit xserver-xorg x11-xserver-utils xterm \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libgbm1 libasound2

# --- Step 2: Set Timezone ---
echo "[2/8] Setting Timezone to $TARGET_TIMEZONE..."
sudo timedatectl set-timezone "$TARGET_TIMEZONE"

# --- CRITICAL PI 5 FIX ---
echo "[3/8] Applying Pi 5 Xorg Fixes..."
# Remove legacy drivers
sudo apt-get remove -y xserver-xorg-video-fbturbo xserver-xorg-video-fbdev
# Force modesetting driver for Pi 5 GPU
sudo mkdir -p /etc/X11/xorg.conf.d
sudo bash -c 'cat > /etc/X11/xorg.conf.d/99-vc4.conf <<EOF
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF'

# --- Step 2: Install Node.js v18 ---
echo "[4/8] Installing Node.js v18..."
export NVM_DIR="$USER_HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 18
nvm use 18
nvm alias default 18

# --- Step 3: Setup Application ---
echo "[5/8] Setting up rpi-infodisplay..."
if [ -d "$REPO_DIR" ]; then
    echo "Updating existing repo..."
    cd "$REPO_DIR"
    # Update origin URL just in case it changed
    git remote set-url origin "$REPO_URL"
    git pull
else
    echo "Cloning $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi
rm -rf node_modules package-lock.json
npm install

# --- Step 4: Generate Configs ---
echo "[6/8] Generating Config Files..."
cat > "$REPO_DIR/config.json" <<EOF
{
  "name": "$NAME",
  "location": "$LOCATION",
  "url": "${TARGET_URL}",
  "fullscreen": true,
  "frame": false,
  "zoomFactor": 1.6,
  "controller": "${CONTROLLER_URL}",
  "refreshCronExpression": "0 0 * * * *"
}
EOF

# .xinitrc for Kiosk mode
cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/sh
xset s off
xset -dpms
xset s noblank
xrandr -s 1920x1080
cd $REPO_DIR
exec npm run start
EOF
chmod +x "$USER_HOME/.xinitrc"

# --- Step 5: Setup Daily Auto-Update (Cron) ---
echo "[7/8] Setting up Daily Auto-Update..."
# Runs at 6:00 AM every day
CRON_CMD="0 6 * * * cd $REPO_DIR && /usr/bin/git pull && /home/$USER/.nvm/versions/node/v18*/bin/npm install"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "git pull") || (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

# --- Step 6: Autologin & Autostart ---
echo "[8/8] Configuring Boot..."
sudo raspi-config nonint do_boot_behaviour B2

PROFILE_FILE="$USER_HOME/.bash_profile"
[ ! -f "$PROFILE_FILE" ] && PROFILE_FILE="$USER_HOME/.bashrc"

if ! grep -q "KIOSK AUTOSTART" "$PROFILE_FILE"; then
cat <<'EOF' >> "$PROFILE_FILE"

# KIOSK AUTOSTART
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
  startx
fi
EOF
fi

echo "=========================================="
echo " Setup Complete! Rebooting in 5 seconds..."
echo "=========================================="
sleep 5
sudo reboot
REMOTE_EOF
    }

    # 3. Transfer the script over SSH
    echo "1. Uploading installer script to $TARGET_IP..."
    # Write the content of get_remote_script to a file on the Pi
    get_remote_script | ssh "$TARGET_USER@$TARGET_IP" "cat > ~/install_kiosk.sh"

    if [ $? -ne 0 ]; then
        echo "Error: Could not connect to $TARGET_IP. Check IP and try again."
        echo ""
        read -p "Do you want to try another Pi? (y/n): " RETRY
        case "$RETRY" in
            [Yy]|[Yy][Ee][Ss])
                continue
                ;;
            *)
                exit 1
                ;;
        esac
    fi

    # 4. Execute the script interactively
    echo "2. Starting remote installation..."
    # -t is crucial here: it opens a pseudo-terminal so you can answer the questions
    ssh -t "$TARGET_USER@$TARGET_IP" "chmod +x ~/install_kiosk.sh && ~/install_kiosk.sh"

    echo "-------------------------------------"
    echo "Deployment finished. Pi is rebooting."
    echo "-------------------------------------"

    # Ask if user wants to deploy to another Pi
    echo ""
    read -p "Do you want to deploy to another Pi? (y/n): " ANOTHER
    case "$ANOTHER" in
        [Yy]|[Yy][Ee][Ss])
            echo "Starting next deployment..."
            ;;
        *)
            echo ""
            echo "============================================"
            echo "      All deployments complete. Goodbye!"
            echo "============================================"
            exit 0
            ;;
    esac
done
