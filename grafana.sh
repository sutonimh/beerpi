#!/bin/bash
# grafana.sh - Version 1.0
# This script uninstalls any existing Grafana installation and related configuration files,
# then installs Grafana on a Raspberry Pi 3B+ using a prebuilt ARM package.
# It prompts whether you are using a 32-bit or 64-bit OS (defaulting to 64-bit) and installs
# the appropriate package. After installation, it sets up Grafana’s systemd service,
# waits for Grafana to fully start, configures the InfluxDB datasource (pointing to the combined_sensor_db),
# and imports a sample dashboard.
#
# WARNING: This script will remove any existing Grafana installation, configuration, dashboards, and datasources.
#
set -e

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please run with sudo."
    exit 1
fi

########################################
# Clean slate: Remove any previous Grafana installation and files.
########################################
echo "Cleaning previous Grafana installation..."
if dpkg -l | grep -q grafana-rpi; then
    systemctl stop grafana-server || true
    dpkg --purge grafana-rpi || true
fi
rm -f /lib/systemd/system/grafana-server.service
rm -rf /etc/grafana
rm -rf /usr/share/grafana
rm -rf /var/lib/grafana
# Delete previous dashboard and datasource via API (if Grafana is running)
curl -s -X DELETE http://admin:admin@localhost:3000/api/dashboards/uid/temperature_dashboard || true
curl -s -X DELETE http://admin:admin@localhost:3000/api/datasources/name/InfluxDB || true

########################################
# Ask for OS architecture.
########################################
read -p "Are you using a 32-bit or 64-bit OS? (Enter 32 or 64, default is 64): " arch_choice
if [ -z "$arch_choice" ]; then
    arch_choice=64
fi

if [ "$arch_choice" == "32" ]; then
    desired_arch="armhf"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana-rpi_9.3.2_armhf.deb"
elif [ "$arch_choice" == "64" ]; then
    desired_arch="arm64"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana-rpi_9.3.2_arm64.deb"
else
    echo "Invalid choice. Defaulting to 64-bit."
    desired_arch="arm64"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana-rpi_9.3.2_arm64.deb"
fi

########################################
# Remove any previously installed Grafana package (if any remain)
########################################
if command -v grafana-server > /dev/null; then
    installed_arch=$(dpkg-query -W -f='${Architecture}' grafana-rpi 2>/dev/null || echo "none")
    if [ "$installed_arch" != "$desired_arch" ]; then
        echo "Installed Grafana architecture ($installed_arch) does not match desired ($desired_arch). Removing..."
        dpkg --purge grafana-rpi || true
    fi
fi

########################################
# Install Grafana via prebuilt ARM package.
########################################
echo "Installing Grafana for ${desired_arch}..."
wget -qO grafana.deb "$grafana_package_url"
dpkg -i grafana.deb || true
apt-get install -y -f
rm grafana.deb

########################################
# Create Grafana systemd unit file if missing.
########################################
SERVICE_FILE="/lib/systemd/system/grafana-server.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating Grafana systemd unit file..."
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Grafana instance
Documentation=http://docs.grafana.org
After=network.target

[Service]
User=grafana
Group=grafana
Type=simple
ExecStart=/usr/sbin/grafana-server --config=/etc/grafana/grafana.ini --homepath=/usr/share/grafana
Restart=always
RestartSec=10
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi

########################################
# Ensure the Grafana user exists.
########################################
if ! id grafana > /dev/null 2>&1; then
    echo "Creating Grafana system user..."
    groupadd --system grafana
    useradd --system --no-create-home --shell /usr/sbin/nologin -g grafana grafana
fi

########################################
# Enable and start the Grafana service.
########################################
echo "Enabling and starting Grafana service..."
systemctl enable grafana-server
systemctl start grafana-server || { echo "ERROR: Failed to start grafana-server service."; exit 1; }
echo "Grafana is installed and running."

########################################
# Wait for Grafana to fully start.
########################################
echo "Waiting 30 seconds for Grafana to fully start..."
sleep 30

########################################
# Configure Grafana InfluxDB datasource.
########################################
echo "Configuring Grafana datasource..."
DS_PAYLOAD=$(cat <<EOF
{
  "name": "InfluxDB",
  "type": "influxdb",
  "access": "proxy",
  "url": "http://localhost:8086",
  "database": "combined_sensor_db",
  "isDefault": true
}
EOF
)
curl -s -X POST -H "Content-Type: application/json" -d "${DS_PAYLOAD}" http://admin:admin@localhost:3000/api/datasources
echo "Grafana datasource configured."

########################################
# Import a sample dashboard into Grafana.
########################################
echo "Importing sample dashboard into Grafana..."
DASHBOARD_JSON=$(cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "temperature_dashboard",
    "title": "Temperature Dashboard",
    "tags": [ "temperature" ],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "panels": [
      {
        "type": "graph",
        "title": "Temperature Over Time",
        "gridPos": { "x": 0, "y": 0, "w": 24, "h": 9 },
        "datasource": "InfluxDB",
        "targets": [
          {
            "measurement": "temperature",
            "groupBy": [
              { "type": "time", "params": [ "$__interval" ] }
            ],
            "select": [
              [
                { "type": "field", "params": [ "temperature" ] }
              ]
            ],
            "refId": "A"
          }
        ],
        "xaxis": { "mode": "time", "show": true },
        "yaxes": [
          { "format": "celsius", "label": "Temperature", "logBase": 1, "show": true },
          { "show": true }
        ]
      }
    ]
  },
  "overwrite": true
}
EOF
)
curl -s -X POST -H "Content-Type: application/json" -d "${DASHBOARD_JSON}" http://admin:admin@localhost:3000/api/dashboards/db
echo "Dashboard imported successfully."

echo "Grafana installation and dashboard configuration complete."
echo "Access Grafana at http://<your_pi_ip>:3000 (username 'admin', password 'admin')."
