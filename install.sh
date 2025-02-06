#!/bin/bash
# install.sh v1.9
set -e

# --- Interactive Prompts ---
read -p "Enter Database Host: " DB_HOST
read -p "Enter Database User: " DB_USER
read -s -p "Enter Database Password: " DB_PASSWORD
echo ""
read -p "Enter Database Name: " DB_DATABASE
read -p "Enter MQTT Broker Address: " MQTT_BROKER
read -p "Enter MQTT Username: " MQTT_USERNAME
read -s -p "Enter MQTT Password: " MQTT_PASSWORD
echo ""

# Store environment variables securely
cat <<EOF >> ~/.bashrc
export DB_HOST="$DB_HOST"
export DB_USER="$DB_USER"
export DB_PASSWORD="$DB_PASSWORD"
export DB_DATABASE="$DB_DATABASE"
export MQTT_BROKER="$MQTT_BROKER"
export MQTT_USERNAME="$MQTT_USERNAME"
export MQTT_PASSWORD="$MQTT_PASSWORD"
EOF

# Create dedicated service user
sudo useradd -r -s /bin/false tempmonitor || true
sudo mkdir -p /home/tempmonitor/temperature_monitor
sudo chown -R tempmonitor:tempmonitor /home/tempmonitor/temperature_monitor

echo "Creating systemd service file..."
SERVICE_FILE="/etc/systemd/system/temp_monitor.service"
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

sudo systemctl daemon-reload
sudo systemctl enable temp_monitor.service
sudo systemctl start temp_monitor.service
