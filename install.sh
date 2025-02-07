#!/bin/bash
# install.sh v3.2
# - Optimized for faster reinstalls
# - Skips reinstalling packages and venv if they already exist
# - Pulls only the latest Git changes instead of full re-clone

set -e  # Exit on error

# Define color codes
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
WHITE="\e[97m"
NC="\e[0m"  # No Color

CONFIG_FILE="$HOME/.beerpi_install_config"

echo -e "\n${YELLOW}🔄 Loading previous installation settings...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}✔️  Previous settings loaded.${NC}"
else
    echo -e "${RED}⚠️  No previous install settings found. Using defaults.${NC}"
fi

# --- Interactive Prompts with Defaults ---
echo -e "\n${YELLOW}🛠️  Configuring Database Settings...${NC}"
read -p "Enter Database Host [$DB_HOST]: " input
DB_HOST="${input:-${DB_HOST:-localhost}}"

read -p "Enter Database User [$DB_USER]: " input
DB_USER="${input:-${DB_USER:-beerpi}}"

read -s -p "Enter Database Password: " DB_PASSWORD
echo ""

read -p "Enter Database Name [$DB_DATABASE]: " input
DB_DATABASE="${input:-${DB_DATABASE:-beerpi_db}}"

echo -e "\n${YELLOW}🔧 Configuring MQTT Settings...${NC}"
read -p "Enter MQTT Broker Address [$MQTT_BROKER]: " input
MQTT_BROKER="${input:-${MQTT_BROKER:-}}"

read -p "Enter MQTT Broker Port (default: 1883): " input
MQTT_PORT="${input:-1883}"

read -p "Enter MQTT Username [$MQTT_USERNAME]: " input
MQTT_USERNAME="${input:-${MQTT_USERNAME:-}}"

read -s -p "Enter MQTT Password: " MQTT_PASSWORD
echo ""

# Save settings (excluding passwords) for future installs
cat <<EOF > "$CONFIG_FILE"
DB_HOST="$DB_HOST"
DB_USER="$DB_USER"
DB_DATABASE="$DB_DATABASE"
MQTT_BROKER="$MQTT_BROKER"
MQTT_PORT="$MQTT_PORT"
MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo -e "${GREEN}✔️  Installation settings saved (except passwords).${NC}"

# Store environment variables securely
echo -e "\n${YELLOW}🔒 Storing environment variables...${NC}"
cat <<EOF >> ~/.bashrc
export DB_HOST="$DB_HOST"
export DB_USER="$DB_USER"
export DB_DATABASE="$DB_DATABASE"
export MQTT_BROKER="$MQTT_BROKER"
export MQTT_PORT="$MQTT_PORT"
export MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo -e "${GREEN}✔️  Environment variables saved. (Restart your session to apply them.)${NC}"

# Install Required Tools (only if missing)
echo -e "\n${YELLOW}🔧 Checking required system packages...${NC}"
REQUIRED_PACKAGES=("mosquitto-clients" "netcat-traditional")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}🔄 Installing missing packages: ${MISSING_PACKAGES[*]}...${NC}"
    sudo apt update && sudo apt install -y "${MISSING_PACKAGES[@]}"
    echo -e "${GREEN}✔️  Required packages installed.${NC}"
else
    echo -e "${GREEN}✔️  All required packages are already installed. Skipping package installation.${NC}"
fi

# Ask if user wants to test MQTT connection
echo -e "\n${YELLOW}🔍 Would you like to test the MQTT connection? (Y/n)${NC}"
read -r TEST_MQTT
if [[ "$TEST_MQTT" =~ ^[Yy]$ || -z "$TEST_MQTT" ]]; then
    echo -e "\n${YELLOW}🔍 Testing MQTT connection to broker at $MQTT_BROKER:$MQTT_PORT...${NC}"
    MQTT_TEST_RESULT=$(mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "test/mqtt" -m "MQTT Test Message" 2>&1)

    if [[ "$MQTT_TEST_RESULT" == *"Connection Refused"* || "$MQTT_TEST_RESULT" == *"Error"* ]]; then
        echo -e "${RED}❌ MQTT Connection Test Failed!${NC}"
        echo -e "${RED}⚠️  Installation will continue, but MQTT may not work correctly.${NC}"
        echo -e "${RED}🛠️  Check your MQTT broker settings and restart the service later.${NC}"
    else
        echo -e "${GREEN}✔️  MQTT Connection Successful! Test message sent.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Skipping MQTT test.${NC}"
fi

# Update repository instead of full re-clone
echo -e "\n${YELLOW}🌍 Updating repository instead of full re-clone...${NC}"
cd /home/tempmonitor/temperature_monitor || { echo -e "${RED}❌ Repo directory missing! Cloning fresh...${NC}"; sudo rm -rf /home/tempmonitor/temperature_monitor; sudo -u tempmonitor git clone https://github.com/sutonimh/beerpi.git /home/tempmonitor/temperature_monitor; }
sudo -u tempmonitor git -C /home/tempmonitor/temperature_monitor pull origin main
echo -e "${GREEN}✔️  Repository updated.${NC}"

# Ensure Virtual Environment Exists
echo -e "\n${YELLOW}🐍 Checking Python virtual environment...${NC}"
cd /home/tempmonitor/temperature_monitor

if [ ! -d "venv" ]; then
    echo -e "${YELLOW}📂 Virtual environment not found, creating one...${NC}"
    sudo -u tempmonitor python3 -m venv venv
    echo -e "${GREEN}✔️  Virtual environment created.${NC}"
else
    echo -e "${GREEN}✔️  Virtual environment already exists. Skipping creation.${NC}"
fi

# Upgrade dependencies
echo -e "\n${YELLOW}📦 Upgrading Python dependencies...${NC}"
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade pip
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade flask plotly mysql-connector-python RPi.GPIO paho-mqtt
echo -e "${GREEN}✔️  Python dependencies upgraded.${NC}"

# Restart the service only if necessary
echo -e "\n${YELLOW}🚀 Restarting temp_monitor.service only if necessary...${NC}"
sudo systemctl is-active --quiet temp_monitor.service && sudo systemctl restart temp_monitor.service || sudo systemctl start temp_monitor.service
echo -e "${GREEN}✔️  Service is now running.${NC}"

# Final Message
echo -e "\n${GREEN}🎉 **Installation Complete!** 🎉${NC}"
echo -e "${GREEN}✅ Temperature monitoring system is now installed and running.${NC}"
echo -e "${WHITE}👉 To check the service status, run: sudo systemctl status temp_monitor.service${NC}"
echo -e "${WHITE}👉 To test MQTT manually, run: mosquitto_pub -h $MQTT_BROKER -p $MQTT_PORT -u $MQTT_USERNAME -P 'your_password' -t 'test/mqtt' -m 'Hello MQTT'${NC}"
echo -e "${WHITE}👉 To access the web UI, go to: http://your-pi-ip:5000${NC}"
echo -e "${GREEN}🚀 Enjoy your BeerPi temperature monitoring system!${NC}"
