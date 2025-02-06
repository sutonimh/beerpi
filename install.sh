#!/bin/bash
# install.sh v2.0
# - Defaults: DB Host (localhost), DB User (beerpi), DB Name (beerpi_db)
# - Remembers previous settings for future installs (except passwords)
# - More verbose confirmation messages
# - Guides user on next steps after installation

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

# Create dedicated service user
echo "👤 Creating dedicated service user 'tempmonitor' (if not exists)..."
sudo useradd -r -s /bin/false tempmonitor || true
sudo mkdir -p /home/tempmonitor/temperature_monitor
sudo chown -R tempmonitor:tempmonitor /home/tempmonitor/temperature_monitor
echo "✅ User 'tempmonitor' setup completed."

# Enable One-Wire
CONFIG_TXT="/boot/firmware/config.txt"
if ! grep -q "dtparam=w1-gpio=on" "$CONFIG_TXT"; then
    echo "⚙️  Enabling One-Wire in $CONFIG_TXT..."
    echo "dtparam=w1-gpio=on" | sudo tee -a "$CONFIG_TXT"
    echo "✅ One-Wire enabled."
fi

echo "🔧 Ensuring One-Wire modules load on boot..."
echo -e "w1_gpio\nw1_therm" | sudo tee /etc/modules-load.d/onewire.conf
sudo modprobe w1-gpio
sudo modprobe w1-therm
echo "✅ One-Wire modules loaded successfully."

# Database Setup
echo "🗄️ Setting up MariaDB database..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_DATABASE};
USE ${DB_DATABASE};
CREATE TABLE IF NOT EXISTS temperature (
    id INT AUTO_INCREMENT PRIMARY KEY,
    value FLOAT,
    datetime DATETIME
);
CREATE TABLE IF NOT EXISTS relay_state (
    id INT AUTO_INCREMENT PRIMARY KEY,
    state VARCHAR(10),
    datetime DATETIME
);
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "✅ Database '${DB_DATABASE}' and user '${DB_USER}' created/verified."

# Clone Repository
if [ ! -d "/home/tempmonitor/temperature_monitor" ]; then
    echo "🌍 Cloning repository..."
    sudo -u tempmonitor git clone https://github.com/sutonimh/beerpi.git /home/tempmonitor/temperature_monitor
    echo "✅ Repository cloned."
else
    echo "🔄 Updating existing repository..."
    sudo -u tempmonitor git -C /home/tempmonitor/temperature_monitor pull origin main
    echo "✅ Repository updated."
fi

# Create Virtual Environment
echo "🐍 Setting up Python virtual environment..."
cd /home/tempmonitor/temperature_monitor
sudo -u tempmonitor python3 -m venv venv
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade pip
sudo -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install flask plotly mysql-connector-python RPi.GPIO paho-mqtt
echo "✅ Python virtual environment and dependencies installed."

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
echo "👉 To view logs, run: **sudo journalctl -u temp_monitor.service -f**"
echo "👉 To access the web UI, go to: **http://your-pi-ip:5000**"
echo "👉 If using MQTT, ensure your Home Assistant is set up to discover new MQTT entities."
echo "🚀 Enjoy your BeerPi temperature monitoring system!"
