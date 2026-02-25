#!/bin/bash

# ==========================================
#  Remote Kiosk Deployer (Run this on PC)
#  Adapted for x64 Fedora Linux 43
# ==========================================

echo "--- Fedora x64 Kiosk Deployer ---"

# Detect local timezone to use as default for remote machine
LOCAL_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Europe/Brussels")

# Main deployment loop
while true; do
    echo ""
    echo "============================================"
    echo "         Starting New Kiosk Deployment"
    echo "============================================"
    echo ""

    # 1. Prompt for Connection Details (Host Side)
    read -p "Enter Target IP Address: " TARGET_IP
    read -p "Enter Target Username [edugo]: " INPUT_USER
    TARGET_USER="${INPUT_USER:-edugo}"
    read -p "Enter Timezone [$LOCAL_TIMEZONE]: " INPUT_TIMEZONE
    TARGET_TIMEZONE="${INPUT_TIMEZONE:-$LOCAL_TIMEZONE}"

    echo "-------------------------------------"
    echo "Target: $TARGET_USER@$TARGET_IP"
    echo "-------------------------------------"

    # 2. Define the Remote Script Content
    #    This function contains the entire installer that runs ON THE TARGET.
    get_remote_script() {
# First, inject the timezone variable (expanded on host side)
cat <<TIMEZONE_EOF
#!/bin/bash
TARGET_TIMEZONE="$TARGET_TIMEZONE"
TIMEZONE_EOF

# Then, the rest of the script (not expanded - single quotes)
cat <<'REMOTE_EOF'

# ==========================================
#  Fedora Kiosk Installer (Running on Target)
# ==========================================

# --- Step 0: User Configuration ---
echo "--- Configuration Setup ---"
echo "Press ENTER to accept default values."
echo ""

# A. Name
read -p "Enter Device Name [fedorakiosk]: " INPUT_NAME
NAME="${INPUT_NAME:-fedorakiosk}"

# B. Location
read -p "Enter Location [location]: " INPUT_LOCATION
LOCATION="${INPUT_LOCATION:-location}"

# C. Display URL
DEFAULT_URL="https://edugo.be"
read -p "Enter Display URL [$DEFAULT_URL]: " INPUT_URL
TARGET_URL="${INPUT_URL:-$DEFAULT_URL}"

# D. Controller URL
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

# --- Step 1: System Updates & Dependencies (Fedora/DNF) ---
echo "[1/7] Installing System Dependencies via DNF..."
sudo dnf upgrade -y

# Installing X11, Git, Cronie, and all Electron/Node required shared libraries
sudo dnf install -y \
    git net-snmp net-snmp-utils pulseaudio-libs gtk3 upower \
    xorg-x11-xinit xorg-x11-server-Xorg xorg-x11-server-utils xterm \
    nss atk at-spi2-atk cups-libs mesa-libgbm alsa-lib cronie \
    tar xz curl wget

# --- Step 2: Set Timezone ---
echo "[2/7] Setting Timezone to $TARGET_TIMEZONE..."
sudo timedatectl set-timezone "$TARGET_TIMEZONE"

# Note: Pi 5 Xorg fixes removed as they are not applicable/needed for x64.

# --- Step 3: Install Node.js v18 ---
echo "[3/7] Installing Node.js v18..."
export NVM_DIR="$USER_HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 18
nvm use 18
nvm alias default 18

# --- Step 4: Setup Application ---
echo "[4/7] Setting up infodisplay..."
if [ -d "$REPO_DIR" ]; then
    echo "Updating existing repo..."
    cd "$REPO_DIR"
    git remote set-url origin "$REPO_URL"
    git pull
else
    echo "Cloning $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi
rm -rf node_modules package-lock.json
npm install

# --- Step 5: Generate Configs ---
echo "[5/7] Generating Config Files..."
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

# --- Step 6: Setup Daily Auto-Update (Cron) ---
echo "[6/7] Setting up Daily Auto-Update..."
# Ensure cron service is enabled and running in Fedora
sudo systemctl enable --now crond

# Runs at 6:00 AM every day
CRON_CMD="0 6 * * * cd $REPO_DIR && /usr/bin/git pull && /home/$USER/.nvm/versions/node/v18*/bin/npm install"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "git pull") || (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

# --- Step 7: Autologin & Autostart (Systemd) ---
echo "[7/7] Configuring Systemd Autologin & Boot..."

# 1. Force the system to boot to CLI/Console (Disables GDM/Wayland desktop login screens)
sudo systemctl set-default multi-user.target

# 2. Create a systemd drop-in to autologin the specific user on tty1
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo bash -c "cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \\\$TERM
EOF"
sudo systemctl daemon-reload

# 3. Trigger startx upon successful tty1 login
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
    get_remote_script | ssh "$TARGET_USER@$TARGET_IP" "cat > ~/install_kiosk.sh"

    if [ $? -ne 0 ]; then
        echo "Error: Could not connect to $TARGET_IP. Check IP and try again."
        echo ""
        read -p "Do you want to try another machine? (y/n): " RETRY
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
    ssh -t "$TARGET_USER@$TARGET_IP" "chmod +x ~/install_kiosk.sh && ~/install_kiosk.sh"

    echo "-------------------------------------"
    echo "Deployment finished. Machine is rebooting."
    echo "-------------------------------------"

    # Ask if user wants to deploy to another machine
    echo ""
    read -p "Do you want to deploy to another machine? (y/n): " ANOTHER
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
