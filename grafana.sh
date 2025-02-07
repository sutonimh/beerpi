#!/bin/bash
# grafana.sh - Version 1.7
# This script uninstalls any existing Grafana installation and related configuration files,
# then installs Grafana on a Raspberry Pi using a prebuilt ARM package.
# It prompts whether you are using a 32-bit or 64-bit OS (defaulting to 64-bit) and installs
# the appropriate package. For 64-bit systems, it downloads the package without the "-rpi" suffix.
#
# Next, it prompts for a Grafana admin username and password (defaulting to admin/admin)
# and updates /etc/grafana/grafana.ini accordingly to avoid forced password resets.
#
# Then, it sets up Grafana’s systemd service, adjusts directory ownership,
# waits for Grafana to fully start, configures the InfluxDB datasource (pointing to the combined_sensor_db),
# and imports a sample dashboard.
#
# WARNING: This script will remove any existing Grafana installation, configuration, dashboards, and datasources.
#
set -e

# Function to print a separator for clarity.
print_sep() {
    echo "----------------------------------------"
}

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please run with sudo."
    exit 1
fi

print_sep
echo "Starting Grafana installation script (Version 1.7) with verbose output."
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
curl -s -X DELETE http://$grafana_user:$grafana_pass@localhost:3000/api/dashboards/uid/temperature_dashboard || true
curl -s -X DELETE http://$grafana_user:$grafana_pass@localhost:3000/api/datasources/name/InfluxDB || true

print_sep

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
    # For 64-bit systems, the package name does not include "-rpi".
    grafana_package_url="https://dl.grafana.com/oss/release/grafana_9.3.2_arm64.deb"
else
    echo "Invalid choice. Defaulting to 64-bit."
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
# Wait for Grafana to fully start.
########################################
echo "Waiting 30 seconds for Grafana to fully start..."
sleep 30
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
curl -s -X POST -H "Content-Type: application/json" -d "${DS_PAYLOAD}" http://${grafana_user}:${grafana_pass}@localhost:3000/api/datasources
echo "Datasource configuration completed."
print_sep

########################################
# Import a sample dashboard into Grafana.
########################################
echo "Importing sample dashboard into Grafana..."
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
curl -s -X POST -H "Content-Type: application/json" -d "${DASHBOARD_JSON}" http://${grafana_user}:${grafana_pass}@localhost:3000/api/dashboards/db
echo "Dashboard imported successfully."
print_sep

echo "Grafana installation and dashboard configuration complete."
echo "Please check Grafana logs (e.g., via 'sudo journalctl -u grafana-server -n 50') if the Web UI at http://<your_pi_ip>:3000 is not loading."
echo "Access Grafana at http://<your_pi_ip>:3000 (credentials: username '${grafana_user}', password '${grafana_pass}')."
