#!/bin/bash
# grafana.sh - Version 2.1
# This merged script sets up Grafana on a Raspberry Pi by performing the following:
#
# 1. Prompts for Grafana admin username and password (default: admin/admin)
# 2. Auto-detects the system architecture (32-bit or 64-bit) and selects the correct Grafana package URL
# 3. If Grafana is not installed, cleans any previous Grafana package/configuration,
#    installs Grafana from the prebuilt ARM package, and creates the systemd unit file.
#    If Grafana is already installed, it skips the package purge/reinstallation.
# 4. Force-updates /etc/grafana/grafana.ini by copying the defaults file (if available) and appending a [security] section with the provided credentials.
# 5. Fixes directory ownership for /usr/share/grafana.
# 6. Restarts Grafana so that the new configuration takes effect.
# 7. Performs a one-time Grafana API health check.
# 8. Verifies the provided credentials via a test API call.
# 9. Calls the secondary import steps (within this same script) to configure the InfluxDB datasource and import the BeerPi Temperature dashboard.
# 10. Verifies by querying the Grafana API that both the datasource and dashboard are present.
#
# WARNING: This script will remove any existing Grafana configuration, dashboards, and datasources.
# It does not force-purge/reinstall the Grafana package if it is already installed.
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
echo "Starting Grafana installation script (Version 2.1) with minimal package reinstallation."
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
# Clean slate for configuration and API objects.
# (Do not purge package if already installed.)
########################################
echo "Removing Grafana systemd unit file and configuration directories if present..."
rm -f /lib/systemd/system/grafana-server.service
# Note: We intentionally do not remove /etc/grafana if Grafana is already installed,
# so as not to purge the package. But if you want a full clean slate, uncomment the next line:
# rm -rf /etc/grafana /usr/share/grafana /var/lib/grafana
# Instead, we will force-update configuration later.
echo "Deleting existing dashboard and datasource via API..."
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
# Install Grafana package if not already installed.
########################################
if ! command -v grafana-server > /dev/null; then
    echo "Grafana is not installed. Proceeding with package installation..."
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
    echo "Grafana package is already installed. Skipping package installation."
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
if [ -f /usr/share/grafana/conf/defaults.ini ]; then
    cp /usr/share/grafana/conf/defaults.ini /etc/grafana/grafana.ini
else
    echo "WARNING: /usr/share/grafana/conf/defaults.ini not found. Skipping config copy."
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
