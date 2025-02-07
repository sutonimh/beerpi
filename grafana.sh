#!/bin/bash
# grafana.sh - Version 2.3
# This merged script sets up Grafana on a Raspberry Pi by performing the following:
#
# 1. Prompts for Grafana admin username and password (default: admin/admin)
# 2. Auto-detects the system architecture (32-bit or 64-bit) and selects the correct Grafana package URL
# 3. If Grafana is not already installed, it removes previous configuration directories and installs the package.
#    If Grafana is already installed, it skips purging the package and preserves existing configuration/data.
# 4. Always removes the systemd unit file (to force recreation) and deletes any existing dashboard/datasource via the API.
# 5. Creates (or recreates) the systemd unit file and ensures the Grafana system user exists.
# 6. Force-updates /etc/grafana/grafana.ini by copying defaults (if available) and appending a [security] section with your credentials.
# 7. Fixes ownership for /usr/share/grafana.
# 8. Restarts Grafana to apply configuration changes.
# 9. Performs a one-time API health check and verifies credentials with a test search.
# 10. Imports the InfluxDB datasource and BeerPi Temperature dashboard via the Grafana API.
# 11. Verifies that the datasource and dashboard are present.
#
# WARNING: This script will delete the systemd unit file and remove dashboards/datasources via the API.
# It will purge configuration directories only if Grafana is not already installed.
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
echo "Starting Grafana installation script (Version 2.3) with minimal delays."
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
# Clean slate for systemd unit and API objects.
########################################
echo "Removing Grafana systemd unit file if present..."
rm -f /lib/systemd/system/grafana-server.service

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
# Determine package name based on architecture.
########################################
if [ "$desired_arch" = "armhf" ]; then
    pkg_name="grafana-rpi"
else
    pkg_name="grafana"
fi
echo "Using package name: ${pkg_name}"
print_sep

########################################
# Check if the correct Grafana package is already installed.
########################################
skip_install=0
if dpkg -l | grep -q "^ii\s\+$pkg_name"; then
    installed_version=$(dpkg-query -W -f='${Version}' $pkg_name 2>/dev/null)
    echo "$pkg_name is already installed with version $installed_version."
    if [ "$installed_version" = "9.3.2" ]; then
        echo "No version change detected. Skipping package reinstallation."
        skip_install=1
    else
        echo "Version change detected. Purging $pkg_name..."
        dpkg --purge $pkg_name || true
        skip_install=0
    fi
else
    echo "$pkg_name is not installed. Will proceed with installation."
fi
print_sep

########################################
# Install Grafana package if needed.
########################################
if [ "$skip_install" -eq 0 ]; then
    echo "Downloading Grafana package from: ${grafana_package_url}"
    wget -O grafana.deb "$grafana_package_url"
    echo "Download completed."
    echo "Installing Grafana package..."
    dpkg -i grafana.deb || true
    echo "Fixing any dependency issues..."
    apt-get install -y -f
    rm grafana.deb
    echo "Grafana package installation completed."
else
    echo "Skipping Grafana package installation."
fi
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
# Force-update Grafana configuration from defaults and set admin credentials.
########################################
echo "Forcing Grafana configuration update..."
# Only remove configuration directories if package is not already installed.
if [ "$skip_install" -eq 0 ]; then
    rm -rf /etc/grafana
fi
mkdir -p /etc/grafana
if [ -f /usr/share/grafana/conf/defaults.ini ]; then
    cp /usr/share/grafana/conf/defaults.ini /etc/grafana/grafana.ini
else
    echo "WARNING: /usr/share/grafana/conf/defaults.ini not found. Creating an empty configuration file."
    touch /etc/grafana/grafana.ini
fi
cat <<EOF >> /etc/grafana/grafana.ini

[security]
admin_user = ${grafana_user}
admin_password = ${grafana_pass}
EOF
echo "Grafana configuration updated with provided credentials."
print_sep

########################################
# Fix ownership of Grafana directories.
########################################
echo "Ensuring correct ownership for /usr/share/grafana..."
if [ ! -d /usr/share/grafana ]; then
    echo "Warning: /usr/share/grafana does not exist. Creating it..."
    mkdir -p /usr/share/grafana
fi
chown -R grafana:grafana /usr/share/grafana || { echo "Failed to fix ownership on /usr/share/grafana"; exit 1; }
print_sep

########################################
# Restart Grafana service to apply configuration changes.
########################################
echo "Restarting Grafana service to apply new configuration..."
systemctl restart grafana-server
sleep 5
echo "Re-checking Grafana service status..."
systemctl status grafana-server --no-pager
print_sep

########################################
# Reapply ownership fix after restart.
########################################
echo "Reapplying ownership fix for /usr/share/grafana..."
chown -R grafana:grafana /usr/share/grafana || { echo "Failed to fix ownership on /usr/share/grafana after restart"; exit 1; }
print_sep

########################################
# Perform a one-time Grafana API health check.
########################################
echo "Performing a one-time Grafana API health check..."
HEALTH=$(curl -s http://localhost:3000/api/health)
echo "Grafana API health check returned: ${HEALTH}"
print_sep

########################################
# Verify credentials by performing a test search.
########################################
echo "Verifying Grafana credentials with a test search..."
SEARCH_RESPONSE=$(curl -s http://${grafana_user}:${grafana_pass}@localhost:3000/api/search?query=dashboard)
echo "Search API response: ${SEARCH_RESPONSE}"
if echo "$SEARCH_RESPONSE" | grep -q '"message"'; then
    echo "WARNING: Search response contains an error message. Credentials may be incorrect."
else
    echo "Credentials appear to be valid."
fi
print_sep

########################################
# Import InfluxDB datasource.
########################################
echo "Importing InfluxDB datasource..."
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
# Import BeerPi Temperature dashboard.
########################################
echo "Importing BeerPi Temperature dashboard..."
DASHBOARD_JSON=$(cat <<EOF
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

########################################
# Verify that the datasource and dashboard have been imported.
########################################
echo "Verifying datasource import..."
DS_CHECK=$(curl -s http://${grafana_user}:${grafana_pass}@localhost:3000/api/datasources/name/InfluxDB)
echo "Datasource check response: ${DS_CHECK}"
if echo "$DS_CHECK" | grep -q '"name":"InfluxDB"'; then
    echo "Datasource verified successfully."
else
    echo "WARNING: Datasource not found. Please check Grafana logs."
fi
print_sep

echo "Verifying dashboard import..."
DB_CHECK=$(curl -s http://${grafana_user}:${grafana_pass}@localhost:3000/api/dashboards/uid/temperature_dashboard)
echo "Dashboard check response: ${DB_CHECK}"
if echo "$DB_CHECK" | grep -q '"title":"BeerPi Temperature"'; then
    echo "Dashboard verified successfully."
else
    echo "WARNING: Dashboard not found. Please check Grafana logs."
fi
print_sep

echo "Grafana installation and dashboard configuration complete."
echo "Please check Grafana logs (e.g., via 'sudo journalctl -u grafana-server -n 50') if the Web UI at http://<your_pi_ip>:3000 is not loading."
echo "Access Grafana at http://<your_pi_ip>:3000 (credentials: username '${grafana_user}', password '${grafana_pass}')."
