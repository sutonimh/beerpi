#!/bin/bash
# grafana.sh - Version 1.4 (last known working split version)
# This script installs Grafana (if not already installed) and updates the configuration file
# with the provided admin credentials.
#
# WARNING: This script will remove the Grafana configuration directory (/etc/grafana)
# so that the credentials and any forced configuration changes take effect.
#
set -e

# Ensure script is run as root.
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo."
  exit 1
fi

# Prompt for admin credentials.
read -p "Enter Grafana admin username (default: admin): " GRAFANA_USER
GRAFANA_USER=${GRAFANA_USER:-admin}
read -sp "Enter Grafana admin password (default: admin): " GRAFANA_PASS
echo
GRAFANA_PASS=${GRAFANA_PASS:-admin}
echo "Using credentials: $GRAFANA_USER / $GRAFANA_PASS"

# Remove the systemd unit file (to force recreation) and clear the configuration.
rm -f /lib/systemd/system/grafana-server.service
rm -rf /etc/grafana
# (Do not remove /usr/share/grafana or /var/lib/grafana so that Grafana’s defaults remain.)

# Auto-detect architecture.
ARCH=$(uname -m)
if [ "$ARCH" = "armv7l" ]; then
  PKG_URL="https://dl.grafana.com/oss/release/grafana-rpi_9.3.2_armhf.deb"
elif [ "$ARCH" = "aarch64" ]; then
  PKG_URL="https://dl.grafana.com/oss/release/grafana_9.3.2_arm64.deb"
else
  echo "Unknown architecture ($ARCH). Defaulting to arm64."
  PKG_URL="https://dl.grafana.com/oss/release/grafana_9.3.2_arm64.deb"
fi

# Check if Grafana is installed.
if dpkg -l | grep -q "^ii\s\+grafana"; then
  echo "Grafana is already installed."
else
  echo "Grafana not installed. Downloading package from $PKG_URL ..."
  wget -O grafana.deb "$PKG_URL"
  dpkg -i grafana.deb || apt-get install -y -f
  rm grafana.deb
fi

# (Re)create the systemd unit file.
cat << 'EOF' > /lib/systemd/system/grafana-server.service
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

# Ensure the Grafana user exists.
if ! id grafana > /dev/null 2>&1; then
  groupadd --system grafana
  useradd --system --no-create-home --shell /usr/sbin/nologin -g grafana grafana
fi

# Update configuration:
# Copy defaults if available; otherwise, create a minimal config.
mkdir -p /etc/grafana
if [ -f /usr/share/grafana/conf/defaults.ini ]; then
  cp /usr/share/grafana/conf/defaults.ini /etc/grafana/grafana.ini
else
  echo "Defaults file not found; creating a minimal configuration."
  cat << EOF > /etc/grafana/grafana.ini
[server]
http_port = 3000
root_url = %(protocol)s://%(domain)s:%(http_port)s/

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins

[log]
mode = console

[log.console]
level = info
format = console
EOF
fi

# Update the [security] section with provided credentials.
if grep -q "^\[security\]" /etc/grafana/grafana.ini; then
  sed -i "s/^;*admin_user.*/admin_user = ${GRAFANA_USER}/" /etc/grafana/grafana.ini
  sed -i "s/^;*admin_password.*/admin_password = ${GRAFANA_PASS}/" /etc/grafana/grafana.ini
else
  cat << EOF >> /etc/grafana/grafana.ini

[security]
admin_user = ${GRAFANA_USER}
admin_password = ${GRAFANA_PASS}
EOF
fi

# Restart Grafana.
systemctl restart grafana-server
sleep 5
systemctl status grafana-server --no-pager

echo "Grafana installation and configuration complete."
echo "You can now run the import script (grafana_import.sh) to import the datasource and dashboard."
