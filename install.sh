#!/bin/bash
# install.sh v3.9
# - Optimized for faster reinstalls
# - Skips reinstalling packages and venv if they already exist
# - Pulls only the latest Git changes instead of full re-clone
# - Installs and configures MariaDB when the database host is localhost
# - Tests the database connection before continuing
# - Prompts for MQTT settings (broker, port, username, and password)
# - Exports DB_PASSWORD via a file (~/.beerpi_db_password) so web_ui.py can connect to MariaDB
# - Informs the user if no temperature sensor is detected (simulated data will be used)

set -e  # Exit on error

# Define color codes
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
WHITE="\e[97m"
NC="\e[0m"  # No Color

CONFIG_FILE="$HOME/.beerpi_install_config"

echo -e "\n${YELLOW}🔄 Loading previous installation settings...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}✔️  Previous settings loaded.${NC}"
else
    echo -e "${RED}⚠️  No previous install settings found. Using defaults.${NC}"
fi

# --- Interactive Prompts for Database Settings ---
echo -e "\n${YELLOW}🛠️  Configuring Database Settings...${NC}"
read -p "Enter Database Host [$DB_HOST]: " input
DB_HOST="${input:-${DB_HOST:-localhost}}"

read -p "Enter Database User [$DB_USER]: " input
DB_USER="${input:-${DB_USER:-beerpi}}"

read -s -p "Enter Database Password: " DB_PASSWORD
echo ""

read -p "Enter Database Name [$DB_DATABASE]: " input
DB_DATABASE="${input:-${DB_DATABASE:-beerpi_db}}"

# Write DB_PASSWORD to a file for services that do not source ~/.bashrc
echo "$DB_PASSWORD" > ~/.beerpi_db_password
chmod 600 ~/.beerpi_db_password

# --- Interactive Prompts for MQTT Settings ---
echo -e "\n${YELLOW}🔧 Configuring MQTT Settings...${NC}"
read -p "Enter MQTT Broker Address [$MQTT_BROKER]: " input
MQTT_BROKER="${input:-${MQTT_BROKER:-192.168.5.12}}"
read -p "Enter MQTT Broker Port [$MQTT_PORT]: " input
MQTT_PORT="${input:-${MQTT_PORT:-1883}}"
read -p "Enter MQTT Username [$MQTT_USERNAME]: " input
MQTT_USERNAME="${input:-${MQTT_USERNAME:-ha_mqtt}}"
read -s -p "Enter MQTT Password: " MQTT_PASSWORD
echo ""

# --- MariaDB Installation and Configuration (if using localhost) ---
if [ "$DB_HOST" == "localhost" ]; then
    echo -e "\n${YELLOW}🔧 Database host is set to localhost.${NC}"
    echo -e "${YELLOW}🔧 Installing MariaDB Server...${NC}"
    sudo apt update && sudo apt install -y mariadb-server
    echo -e "${GREEN}✔️  MariaDB Server installed.${NC}"

    echo -e "\n${YELLOW}🔧 Configuring MariaDB for BeerPi...${NC}"
    echo -e "${YELLOW}🔧 Creating database '${DB_DATABASE}' (if it doesn't exist)...${NC}"
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\`;" && echo -e "${GREEN}✔️  Database '${DB_DATABASE}' ensured.${NC}"
    
    echo -e "${YELLOW}🔧 Creating user '${DB_USER}' (if it doesn't exist) and setting its password...${NC}"
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" && echo -e "${GREEN}✔️  User '${DB_USER}' ensured.${NC}"
    
    echo -e "${YELLOW}🔧 Granting privileges on '${DB_DATABASE}' to user '${DB_USER}'...${NC}"
    sudo mysql -e "GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USER}'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;" && echo -e "${GREEN}✔️  Privileges granted and flushed.${NC}"
fi

# --- Test the Database Connection ---
echo -e "\n${YELLOW}🔍 Testing database connection to '${DB_DATABASE}' on host '${DB_HOST}'...${NC}"
if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e "USE \`${DB_DATABASE}\`;" >/dev/null 2>&1; then
    echo -e "${GREEN}✔️  Database connection successful.${NC}"
else
    echo -e "${RED}❌ Failed to connect to the database. Please check your configuration.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}🔧 Saving configuration settings...${NC}"
# Save settings (excluding passwords) for future installs
cat <<EOF > "$CONFIG_FILE"
DB_HOST="$DB_HOST"
DB_USER="$DB_USER"
DB_DATABASE="$DB_DATABASE"
MQTT_BROKER="$MQTT_BROKER"
MQTT_PORT="$MQTT_PORT"
MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo -e "${GREEN}✔️  Configuration settings saved (except passwords).${NC}"

# Store environment variables securely (now including DB_PASSWORD)
echo -e "\n${YELLOW}🔒 Storing environment variables...${NC}"
cat <<EOF >> ~/.bashrc
export DB_HOST="$DB_HOST"
export DB_USER="$DB_USER"
export DB_DATABASE="$DB_DATABASE"
export DB_PASSWORD="$DB_PASSWORD"
export MQTT_BROKER="$MQTT_BROKER"
export MQTT_PORT="$MQTT_PORT"
export MQTT_USERNAME="$MQTT_USERNAME"
EOF
echo -e "${GREEN}✔️  Environment variables saved. (Restart your session to apply them.)${NC}"

# Install Required Tools (only if missing)
echo -e "\n${YELLOW}🔧 Checking required system packages...${NC}"
REQUIRED_PACKAGES=("mosquitto-clients" "netcat-traditional")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}🔄 Installing missing packages: ${MISSING_PACKAGES[*]}...${NC}"
    sudo apt update && sudo apt install -y "${MISSING_PACKAGES[@]}"
    echo -e "${GREEN}✔️  Required packages installed.${NC}"
else
    echo -e "${GREEN}✔️  All required packages are already installed. Skipping package installation.${NC}"
fi

# Ask if user wants to test MQTT connection
echo -e "\n${YELLOW}🔍 Would you like to test the MQTT connection? (Y/n)${NC}"
read -r TEST_MQTT
if [[ "$TEST_MQTT" =~ ^[Yy]$ || -z "$TEST_MQTT" ]]; then
    echo -e "\n${YELLOW}🔍 Testing MQTT connection to broker at $MQTT_BROKER:$MQTT_PORT...${NC}"
    MQTT_TEST_RESULT=$(mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "test/mqtt" -m "MQTT Test Message" 2>&1)

    if [[ "$MQTT_TEST_RESULT" == *"Connection Refused"* || "$MQTT_TEST_RESULT" == *"Error"* ]]; then
        echo -e "${RED}❌ MQTT Connection Test Failed!${NC}"
        echo -e "${RED}⚠️  Installation will continue, but MQTT may not work correctly.${NC}"
        echo -e "${RED}🛠️  Check your MQTT broker settings and restart the service later.${NC}"
    else
        echo -e "${GREEN}✔️  MQTT Connection Successful! Test message sent.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Skipping MQTT test.${NC}"
fi

# Update repository instead of full re-clone
echo -e "\n${YELLOW}🌍 Updating repository instead of full re-clone...${NC}"
cd /home/tempmonitor/temperature_monitor || { echo -e "${RED}❌ Repo directory missing! Cloning fresh...${NC}"; sudo rm -rf /home/tempmonitor/temperature_monitor; sudo -u tempmonitor git clone https://github.com/sutonimh/beerpi.git /home/tempmonitor/temperature_monitor; }
sudo -u tempmonitor git -C /home/tempmonitor/temperature_monitor pull origin main
echo -e "${GREEN}✔️  Repository updated.${NC}"

# Ensure Virtual Environment Exists
echo -e "\n${YELLOW}🐍 Checking Python virtual environment...${NC}"
cd /home/tempmonitor/temperature_monitor

if [ ! -d "venv" ]; then
    echo -e "${YELLOW}📂 Virtual environment not found, creating one...${NC}"
    sudo -u tempmonitor python3 -m venv venv
    echo -e "${GREEN}✔️  Virtual environment created.${NC}"
else
    echo -e "${GREEN}✔️  Virtual environment already exists. Skipping creation.${NC}"
fi

# Upgrade dependencies
echo -e "\n${YELLOW}📦 Upgrading Python dependencies...${NC}"
sudo -H -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade pip
sudo -H -u tempmonitor /home/tempmonitor/temperature_monitor/venv/bin/pip install --upgrade flask plotly mysql-connector-python RPi.GPIO paho-mqtt
echo -e "${GREEN}✔️  Python dependencies upgraded.${NC}"

# Restart the service only if necessary
echo -e "\n${YELLOW}🚀 Restarting temp_monitor.service only if necessary...${NC}"
sudo systemctl is-active --quiet temp_monitor.service && sudo systemctl restart temp_monitor.service || sudo systemctl start temp_monitor.service
echo -e "${GREEN}✔️  Service is now running.${NC}"

# --- Sensor Detection Message ---
# Check for DS18B20 sensor in /sys/bus/w1/devices/28-*
shopt -s nullglob
sensor_array=(/sys/bus/w1/devices/28-*)
if [ ${#sensor_array[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No temperature sensor detected. Simulated data will be used until you connect a sensor and restart the Raspberry Pi.${NC}"
fi

# Final Message
echo -e "\n${GREEN}🎉 **Installation Complete!** 🎉${NC}"
echo -e "${GREEN}✅ Temperature monitoring system is now installed and running.${NC}"
echo -e "${WHITE}👉 To check the service status, run: sudo systemctl status temp_monitor.service${NC}"
echo -e "${WHITE}👉 To test MQTT manually, run: mosquitto_pub -h $MQTT_BROKER -p $MQTT_PORT -u $MQTT_USERNAME -P 'your_password' -t 'test/mqtt' -m 'Hello MQTT'${NC}"
echo -e "${WHITE}👉 To access the web UI, go to: http://your-pi-ip:5000${NC}"
echo -e "${GREEN}🚀 Enjoy your BeerPi temperature monitoring system!${NC}"
