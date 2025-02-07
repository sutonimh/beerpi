#!/bin/bash
# grafana.sh - Version 1.15
# This script sets up Grafana on a Raspberry Pi by performing the following:
#  - Prompts for Grafana admin username and password (default: admin/admin)
#  - Auto-detects the system architecture (32-bit or 64-bit) and selects the correct Grafana package URL
#  - Removes any previous Grafana installation and configuration files
#  - Installs Grafana from the prebuilt ARM package
#  - Updates /etc/grafana/grafana.ini with the provided admin credentials to avoid forced password resets
#  - Ensures correct directory ownership for Grafana (/usr/share/grafana)
#  - Creates and starts the Grafana systemd service
#  - Waits until Grafana’s API (/api/health) reports healthy ("database" : "ok")
#  - Calls a secondary import script (grafana_import.sh) to configure the InfluxDB datasource and import the dashboard
#  - Verifies that the datasource and dashboard are present by querying the Grafana API
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
echo "Starting Grafana installation script (Version 1.15) with verbose output."
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
# (Optional) Re-run ownership fix after restart, in case service re-created files.
########################################
echo "Reapplying ownership fix for /usr/share/grafana..."
chown -R grafana:grafana /usr/share/grafana || { echo "Failed to fix ownership on /usr/share/grafana after restart"; exit 1; }
print_sep

########################################
# Wait for Grafana API to be available.
########################################
echo "Waiting for Grafana API to become available..."
HEALTH=$(curl -s http://localhost:3000/api/health)
echo "Grafana API health check returned: ${HEALTH}"
retry=0
max_retries=30
until echo "$HEALTH" | grep -E -q '"database"[[:space:]]*:[[:space:]]*"ok"'; do
    echo "Grafana API not ready. Waiting 5 seconds... (retry: $((retry+1))/$max_retries)"
    sleep 5
    HEALTH=$(curl -s http://localhost:3000/api/health)
    echo "Grafana API health check returned: ${HEALTH}"
    retry=$((retry+1))
    if [ $retry -ge $max_retries ]; then
        echo "ERROR: Grafana API did not become ready after $max_retries retries."
        exit 1
    fi
done
echo "Grafana API is available."
print_sep

########################################
# Verify credentials by performing a simple search.
########################################
echo "Verifying Grafana credentials with a test search..."
SEARCH_RESPONSE=$(curl -s http://${grafana_user}:${grafana_pass}@localhost:3000/api/search?query=dashboard)
echo "Search API response: ${SEARCH_RESPONSE}"
if echo "$SEARCH_RESPONSE" | grep -q '"message"'; then
    echo "WARNING: Search response contains an error message."
else
    echo "Credentials appear to be valid."
fi
print_sep

########################################
# Call secondary import script to configure datasource and dashboard.
########################################
echo "Running secondary import script (grafana_import.sh)..."
export GRAFANA_USER=${grafana_user}
export GRAFANA_PASS=${grafana_pass}
if [ -f ./grafana_import.sh ]; then
    ./grafana_import.sh
else
    echo "Secondary import script (grafana_import.sh) not found, skipping datasource and dashboard import."
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
