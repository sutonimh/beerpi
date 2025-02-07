#!/bin/bash
# install.sh v3.0
# - Adds colored output for better readability
# - Uses green for successes, red for warnings/errors, blue for general info
# - Improves spacing and tab alignment for legibility

set -e  # Exit on error

# Define color codes
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
NC="\e[0m"  # No Color

CONFIG_FILE="$HOME/.beerpi_install_config"

echo -e "\n${BLUE}🔄 Loading previous installation settings...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}✔️  Previous settings loaded.${NC}"
else
    echo -e "${RED}⚠️  No previous install settings found. Using defaults.${NC}"
fi

# --- Interactive Prompts with Defaults ---
echo -e "\n${BLUE}🛠️  Configuring Database Settings...${NC}"
read -p "Enter Database Host [$DB_HOST]: " input
DB_HOST="${input:-${DB_HOST:-localhost}}"

read -p "Enter Database User [$DB_USER]: " input
DB_USER="${input:-${DB_USER:-beerpi}}"

read -s -p "Enter Database Password: " DB_PASSWORD
echo ""

read -p "Enter Database Name [$DB_DATABASE]: " input
DB_DATABASE="${input:-${DB_DATABASE:-beerpi_db}}"

echo -e "\n${BLUE}🔧 Configuring MQTT Settings...${NC}"
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
echo -e "\n${BLUE}🔒 Storing environment variables...${NC}"
cat <<EOF >> ~/.bashrc
export DB_HOST="$DB_HOST"
export DB_USER="$DB_USER"
export DB_DATABASE="$DB_DATABASE"
export MQTT_BROKER="$MQTT_BROKER"
export MQTT_PORT="$MQTT_PORT"
export MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo -e "${GREEN}✔️  Environment variables saved. (Restart your session to apply them.)${NC}"

# Install Required Tools
echo -e "\n${BLUE}🔧 Installing Mosquitto clients and Netcat-Traditional for MQTT testing...${NC}"
sudo apt update
sudo apt install -y mosquitto-clients netcat-traditional
echo -e "${GREEN}✔️  Mosquitto clients and Netcat-Traditional installed.${NC}"

# --- MQTT Connection Test ---
echo -e "\n${BLUE}🔍 Testing MQTT connection to broker at $MQTT_BROKER:$MQTT_PORT...${NC}"
MQTT_TEST_RESULT=$(mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "test/mqtt" -m "MQTT Test Message" 2>&1)

if [[ "$MQTT_TEST_RESULT" == *"Connection Refused"* || "$MQTT_TEST_RESULT" == *"Error"* ]]; then
    echo -e "${RED}❌ MQTT Connection Test Failed!${NC}"
    echo -e "${RED}⚠️  Installation will continue, but MQTT may not work correctly.${NC}"
    echo -e "${RED}🛠️  Check your MQTT broker settings and restart the service later.${NC}"
else
    echo -e "${GREEN}✔️  MQTT Connection Successful! Test message sent.${NC}"
fi

# Ensure correct permissions for repo
echo -e "\n${BLUE}🌍 Resetting the repository (removing old files)...${NC}"
sudo rm -rf /home/tempmonitor/temperature_monitor
sudo mkdir -p /home/tempmonitor/temperature_monitor
sudo chown -R tempmonitor:tempmonitor /home/tempmonitor/temperature_monitor
sudo chmod -R 755 /home/tempmonitor/temperature_monitor
echo -e "${BLUE}📂 Cloning repository as 'tempmonitor'...${NC}"
sudo -u tempmonitor git clone https://github.com/sutonimh/beerpi.git /home/tempmonitor/temperature_monitor
echo -e "${GREEN}✔️  Repository fully re-cloned.${NC}"

# Ensure Virtual Environment Exists
echo -e "\n${BLUE}🐍 Checking Python virtual environment...${NC}"
cd /home/tempmonitor/temperature_monitor

if [ ! -d "venv" ]; then
    echo -e "${BLUE}📂 Virtual environment not found, creating one...${NC}"
    sudo -u tempmonitor python3 -m venv venv
    echo -e "${GREEN}✔️  Virtual environment created.${NC}"
else
    echo -e "${GREEN}✔️  Virtual environment already exists. Skipping creation.${NC}"
fi

# Upgrade dependencies
echo -e "\n${BLUE}📦 Upgrading Python dependencies...${NC}"
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade pip
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade flask plotly mysql-connector-python RPi.GPIO paho-mqtt
echo -e "${GREEN}✔️  Python dependencies upgraded.${NC}"

# Create Systemd Service
SERVICE_FILE="/etc/systemd/system/temp_monitor.service"
echo -e "\n${BLUE}⚙️  Creating systemd service file...${NC}"
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Temperature Monitoring and Relay Control Service
After=network.target

[Service]
User=tempmonitor
WorkingDirectory=/home/tempmonitor/temperature_monitor
ExecStart=/home/tempmonitor/temperature_monitor/venv/bin/python /home/tempmonitor/temperature_monitor/temp_control.py
Restart=always
Environment="PATH=/home/tempmonitor/temperature_monitor/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✔️  Systemd service file created.${NC}"

# Enable and Start Service
echo -e "\n${BLUE}🚀 Enabling and starting temp_monitor.service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable temp_monitor.service
sudo systemctl restart temp_monitor.service
echo -e "${GREEN}✔️  Service is now running.${NC}"

# Final Message
echo -e "\n${GREEN}🎉 **Installation Complete!** 🎉${NC}"
echo -e "${GREEN}✅ Temperature monitoring system is now installed and running.${NC}"
echo -e "👉 To check the service status, run:  ${BLUE}sudo systemctl status temp_monitor.service${NC}"
echo -e "👉 To test MQTT manually, run: ${BLUE}mosquitto_pub -h $MQTT_BROKER -p $MQTT_PORT -u $MQTT_USERNAME -P 'your_password' -t 'test/mqtt' -m 'Hello MQTT'${NC}"
echo -e "👉 To access the web UI, go to: ${BLUE}http://your-pi-ip:5000${NC}"
echo -e "${GREEN}🚀 Enjoy your BeerPi temperature monitoring system!${NC}"
