#!/bin/bash
# install.sh v2.6
# - Supports modular MQTT setup (`mqtt_handler.py`)
# - Installs `mosquitto-clients` and `netcat` for MQTT debugging
# - Preserves virtual environment (`venv`)
# - Keeps previous install settings (except passwords)
# - Fixes permissions before cloning repo

set -e  # Exit on error

CONFIG_FILE="$HOME/.beerpi_install_config"

# Load previous settings if available
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo "🔄 Previous installation settings loaded."
else
    echo "🆕 No previous install settings found. Using defaults."
fi

# --- Interactive Prompts with Defaults ---
read -p "Enter Database Host [$DB_HOST]: " input
DB_HOST="${input:-${DB_HOST:-localhost}}"

read -p "Enter Database User [$DB_USER]: " input
DB_USER="${input:-${DB_USER:-beerpi}}"

read -s -p "Enter Database Password: " DB_PASSWORD
echo ""

read -p "Enter Database Name [$DB_DATABASE]: " input
DB_DATABASE="${input:-${DB_DATABASE:-beerpi_db}}"

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
echo "✅ Installation settings saved (except passwords)."

# Store environment variables securely
echo "🔒 Storing environment variables..."
cat <<EOF >> ~/.bashrc
export DB_HOST="$DB_HOST"
export DB_USER="$DB_USER"
export DB_DATABASE="$DB_DATABASE"
export MQTT_BROKER="$MQTT_BROKER"
export MQTT_PORT="$MQTT_PORT"
export MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo "✅ Environment variables saved. (You must restart your session to apply them.)"

# Install Required Tools
echo "🔧 Installing Mosquitto clients and Netcat for MQTT testing..."
sudo apt update
sudo apt install -y mosquitto-clients netcat
echo "✅ Mosquitto clients and Netcat installed."

# Ensure correct permissions for repo
echo "🌍 Resetting the repository (removing old files)..."
sudo rm -rf /home/tempmonitor/temperature_monitor
sudo mkdir -p /home/tempmonitor/temperature_monitor
sudo chown -R tempmonitor:tempmonitor /home/tempmonitor/temperature_monitor
sudo chmod -R 755 /home/tempmonitor/temperature_monitor
echo "📂 Cloning repository as 'tempmonitor'..."
sudo -u tempmonitor git clone https://github.com/sutonimh/beerpi.git /home/tempmonitor/temperature_monitor
echo "✅ Repository fully re-cloned."

# Ensure Virtual Environment Exists
echo "🐍 Checking Python virtual environment..."
cd /home/tempmonitor/temperature_monitor

if [ ! -d "venv" ]; then
    echo "📂 Virtual environment not found, creating one..."
    sudo -u tempmonitor python3 -m venv venv
    echo "✅ Virtual environment created."
else
    echo "🔄 Virtual environment already exists. Skipping creation."
fi

# Upgrade dependencies
echo "📦 Upgrading Python dependencies..."
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade pip
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade flask plotly mysql-connector-python RPi.GPIO paho-mqtt
echo "✅ Python dependencies upgraded."

# Create Systemd Service
SERVICE_FILE="/etc/systemd/system/temp_monitor.service"
echo "⚙️  Creating systemd service file..."
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
echo "✅ Systemd service file created."

# Enable and Start Service
echo "🚀 Enabling and starting temp_monitor.service..."
sudo systemctl daemon-reload
sudo systemctl enable temp_monitor.service
sudo systemctl restart temp_monitor.service
echo "✅ Service is now running."

# Final Message
echo ""
echo "🎉 **Installation Complete!** 🎉"
echo "✅ Temperature monitoring system is now installed and running."
echo "👉 To check the service status, run:  **sudo systemctl status temp_monitor.service**"
echo "👉 To test MQTT, run: **mosquitto_pub -h $MQTT_BROKER -p $MQTT_PORT -u $MQTT_USERNAME -P 'your_password' -t 'test/topic' -m 'Hello MQTT'**"
echo "👉 To access the web UI, go to: **http://your-pi-ip:5000**"
echo "🚀 Enjoy your BeerPi temperature monitoring system!"
