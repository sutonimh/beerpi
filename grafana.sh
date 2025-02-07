#!/bin/bash
# grafana.sh - Version 1.10
# This script sets up Grafana on a Raspberry Pi by performing the following:
#  - Prompts for Grafana admin username and password (default: admin/admin)
#  - Auto-detects the system architecture (32-bit or 64-bit) and selects the correct Grafana package URL
#  - Removes any previous Grafana installation and configuration files
#  - Installs Grafana from the prebuilt ARM package
#  - Updates /etc/grafana/grafana.ini with the provided admin credentials to avoid forced password resets
#  - Ensures correct directory ownership for Grafana
#  - Creates and starts the Grafana systemd service
#  - Waits until Grafana’s API is fully available (by polling /api/health)
#  - Configures an InfluxDB datasource (pointing to the combined_sensor_db) via the API and checks the result
#  - Imports the BeerPi Temperature dashboard (which displays the temperature data) and checks the result
#
# WARNING: This script will remove any existing Grafana installation, configuration, dashboards, and datasources.
#
set -e

# Function to print a separator.
print_sep() {
    echo "----------------------------------------"
}

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please run with sudo."
    exit 1
fi

print_sep
echo "Starting Grafana installation script (Version 1.10) with verbose output."
print_sep

########################################
# Prompt for Grafana admin credentials.
########################################
read -p "Enter Grafana admin username (default: admin): " grafana_user
if [ -z "$grafana_user" ]; then
    grafana_user="admin"
fi
read -sp "Enter Grafana admin password (default: admin): " grafana_pass
echo
if [ -z "$grafana_pass" ]; then
    grafana_pass="admin"
fi
echo "Using Grafana admin credentials: ${grafana_user} / ${grafana_pass}"
print_sep

########################################
# Clean slate: Remove any previous Grafana installation and files.
########################################
echo "Cleaning previous Grafana installation..."
if dpkg -l | grep -q grafana-rpi; then
    echo "Found existing Grafana package. Stopping Grafana service..."
    systemctl stop grafana-server || true
    echo "Purging existing Grafana package..."
    dpkg --purge grafana-rpi || true
else
    echo "No existing Grafana package found."
fi

echo "Removing Grafana systemd unit file and configuration directories if present..."
rm -f /lib/systemd/system/grafana-server.service
rm -rf /etc/grafana /usr/share/grafana /var/lib/grafana

echo "Attempting to delete any existing Grafana dashboard/datasource via API..."
curl -s -X DELETE http://${grafana_user}:${grafana_pass}@localhost:3000/api/dashboards/uid/temperature_dashboard || true
curl -s -X DELETE http://${grafana_user}:${grafana_pass}@localhost:3000/api/datasources/name/InfluxDB || true
print_sep

########################################
# Auto-detect OS architecture.
########################################
ARCH=$(uname -m)
echo "Detected architecture from uname -m: $ARCH"
if [ "$ARCH" = "armv7l" ]; then
    desired_arch="armhf"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana-rpi_9.3.2_armhf.deb"
elif [ "$ARCH" = "aarch64" ]; then
    desired_arch="arm64"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana_9.3.2_arm64.deb"
else
    echo "Unknown architecture: $ARCH. Defaulting to 64-bit."
    desired_arch="arm64"
    grafana_package_url="https://dl.grafana.com/oss/release/grafana_9.3.2_arm64.deb"
fi
echo "Selected architecture: ${desired_arch}"
print_sep

########################################
# Remove any previously installed Grafana package (if any remain)
########################################
if command -v grafana-server > /dev/null; then
    installed_arch=$(dpkg-query -W -f='${Architecture}' grafana-rpi 2>/dev/null || echo "none")
    echo "Previously installed Grafana architecture: $installed_arch"
    if [ "$installed_arch" != "$desired_arch" ]; then
        echo "Installed Grafana architecture ($installed_arch) does not match desired ($desired_arch). Removing..."
        dpkg --purge grafana-rpi || true
    else
        echo "Grafana is already installed with the desired architecture ($installed_arch)."
    fi
fi
print_sep

########################################
# Install Grafana via prebuilt ARM package.
########################################
echo "Downloading Grafana package from: ${grafana_package_url}"
wget -O grafana.deb "$grafana_package_url"
echo "Download completed."
echo "Installing Grafana package..."
dpkg -i grafana.deb || true
echo "Fixing any dependency issues..."
apt-get install -y -f
rm grafana.deb
echo "Grafana package installation completed."
print_sep

########################################
# Create Grafana systemd unit file if missing.
########################################
SERVICE_FILE="/lib/systemd/system/grafana-server.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Grafana systemd unit file not found. Creating it..."
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
    echo "Reloading systemd daemon..."
    systemctl daemon-reload
else
    echo "Grafana systemd unit file already exists."
fi
print_sep

########################################
# Ensure the Grafana user exists.
########################################
if ! id grafana > /dev/null 2>&1; then
    echo "Grafana user not found. Creating system user 'grafana'..."
    groupadd --system grafana
    useradd --system --no-create-home --shell /usr/sbin/nologin -g grafana grafana
else
    echo "Grafana system user exists."
fi
print_sep

########################################
# Update Grafana configuration to set admin credentials.
########################################
if [ -f /etc/grafana/grafana.ini ]; then
    echo "Updating Grafana configuration with admin credentials..."
    if grep -q "^\[security\]" /etc/grafana/grafana.ini; then
        sed -i "s/^;*admin_user.*/admin_user = ${grafana_user}/" /etc/grafana/grafana.ini
        sed -i "s/^;*admin_password.*/admin_password = ${grafana_pass}/" /etc/grafana/grafana.ini
    else
        echo "[security]" >> /etc/grafana/grafana.ini
        echo "admin_user = ${grafana_user}" >> /etc/grafana/grafana.ini
        echo "admin_password = ${grafana_pass}" >> /etc/grafana/grafana.ini
    fi
    echo "Grafana configuration updated."
else
    echo "WARNING: /etc/grafana/grafana.ini not found. Grafana may not be configured correctly."
fi
print_sep

########################################
# Fix ownership of Grafana directories to prevent permission errors.
########################################
echo "Ensuring correct ownership for /usr/share/grafana..."
chown -R grafana:grafana /usr/share/grafana
print_sep

########################################
# Enable and start the Grafana service.
########################################
echo "Enabling Grafana service..."
systemctl enable grafana-server
echo "Starting Grafana service..."
systemctl start grafana-server || { echo "ERROR: Failed to start grafana-server service."; exit 1; }
sleep 5
echo "Checking Grafana service status..."
systemctl status grafana-server --no-pager
print_sep

########################################
# Wait for Grafana API to be available.
########################################
echo "Waiting for Grafana API to become available..."
until curl -s http://${grafana_user}:${grafana_pass}@localhost:3000/api/health | grep -q '"database":"ok"'; do
    echo "Grafana API not ready. Waiting 5 seconds..."
    sleep 5
done
echo "Grafana API is available."
print_sep

########################################
# Configure Grafana InfluxDB datasource.
########################################
echo "Configuring Grafana InfluxDB datasource..."
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
echo "Sending datasource configuration to Grafana API..."
DS_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "${DS_PAYLOAD}" http://${grafana_user}:${grafana_pass}@localhost:3000/api/datasources)
echo "Datasource API response: ${DS_RESPONSE}"
if echo "$DS_RESPONSE" | grep -q '"message":"Datasource added"'; then
    echo "Datasource configured successfully."
else
    echo "WARNING: Datasource configuration may have failed. Please check the response above."
fi
print_sep

########################################
# Import the BeerPi Temperature dashboard into Grafana.
########################################
echo "Importing BeerPi Temperature dashboard into Grafana..."
DASHBOARD_JSON=$(cat <<'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "temperature_dashboard",
    "title": "BeerPi Temperature",
    "folderId": 0,
    "tags": [ "temperature" ],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 1,
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
                { "type": "field", "params": [ "temperature" ] },
                { "type": "mean", "params": [] }
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
echo "Sending dashboard JSON to Grafana API..."
DB_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "${DASHBOARD_JSON}" http://${grafana_user}:${grafana_pass}@localhost:3000/api/dashboards/db)
echo "Dashboard API response: ${DB_RESPONSE}"
if echo "$DB_RESPONSE" | grep -q '"status":"success"'; then
    echo "Dashboard imported successfully."
else
    echo "WARNING: Dashboard import may have failed. Please check the response above."
fi
print_sep

echo "Grafana installation and dashboard configuration complete."
echo "Please check Grafana logs (e.g., via 'sudo journalctl -u grafana-server -n 50') if the Web UI at http://<your_pi_ip>:3000 is not loading."
echo "Access Grafana at http://<your_pi_ip>:3000 (credentials: username '${grafana_user}', password '${grafana_pass}')."
