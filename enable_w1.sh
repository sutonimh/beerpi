#!/bin/bash
# Verbose script to enable the 1-wire interface on a user-confirmed GPIO pin and detect a sensor.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "========== Starting 1-Wire Setup Script =========="

# Ensure the script is run as root.
echo "Checking for root privileges..."
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please try again using sudo."
    exit 1
else
    echo "Root privileges confirmed (UID=$(id -u))."
fi

# Prompt the user to specify the GPIO pin number (default is 4)
DEFAULT_GPIO=4
read -p "Enter the GPIO pin number the sensor is connected to (default is $DEFAULT_GPIO): " user_input
if [ -z "$user_input" ]; then
    gpio_pin=$DEFAULT_GPIO
else
    gpio_pin=$user_input
fi

echo "You have selected GPIO pin: $gpio_pin"
read -p "Is this correct? [Y/n]: " confirmation
if [[ $confirmation =~ ^[Nn] ]]; then
    echo "Aborting script. Please re-run and provide the correct GPIO pin."
    exit 1
fi

CONFIG_FILE="/boot/config.txt"
OVERLAY_LINE="dtoverlay=w1-gpio,gpiopin=${gpio_pin}"

echo "--------------------------------------------------"
echo "Checking for 1-wire configuration in ${CONFIG_FILE}..."
echo "Looking for the line: '${OVERLAY_LINE}'"

# Check if the overlay line exists (even if commented out)
if grep -q "^[#]*\s*${OVERLAY_LINE}" "$CONFIG_FILE"; then
    echo "Found an entry for 1-wire in ${CONFIG_FILE}."
    # If it's commented out, uncomment it.
    if grep -q "^#\s*${OVERLAY_LINE}" "$CONFIG_FILE"; then
        echo "The overlay line is currently commented out. Uncommenting it..."
        sed -i "s/^#\s*\(${OVERLAY_LINE}\)/\1/" "$CONFIG_FILE"
        echo "The overlay line has been uncommented."
        echo "NOTE: A reboot is recommended for changes to take effect."
    else
        echo "The overlay line is already active. No changes needed."
    fi
else
    echo "No 1-wire overlay entry found in ${CONFIG_FILE}."
    echo "Appending the following lines to ${CONFIG_FILE}:"
    echo "    # Enable 1-wire interface on GPIO${gpio_pin}"
    echo "    ${OVERLAY_LINE}"
    {
        echo ""
        echo "# Enable 1-wire interface on GPIO${gpio_pin}"
        echo "${OVERLAY_LINE}"
    } >> "$CONFIG_FILE"
    echo "Overlay line added successfully."
    echo "NOTE: A reboot is recommended for changes to take effect."
fi

echo "--------------------------------------------------"
echo "Loading kernel modules required for 1-wire interface..."
echo "Loading module: w1-gpio"
if modprobe w1-gpio; then
    echo "Module w1-gpio loaded successfully."
else
    echo "ERROR: Failed to load module w1-gpio."
fi

echo "Loading module: w1-therm"
if modprobe w1-therm; then
    echo "Module w1-therm loaded successfully."
else
    echo "ERROR: Failed to load module w1-therm."
fi

echo "--------------------------------------------------"
echo "Waiting for the system to register the sensor..."
WAIT_TIME=5
echo "Sleeping for ${WAIT_TIME} seconds..."
sleep ${WAIT_TIME}

W1_DEVICES="/sys/bus/w1/devices"
echo "Scanning for 1-wire devices in ${W1_DEVICES}..."
if [ ! -d "${W1_DEVICES}" ]; then
    echo "ERROR: Directory ${W1_DEVICES} does not exist. Ensure that 1-wire is enabled and modules are loaded."
    exit 1
fi

# Find directories that start with "28-" (common for DS18B20 sensors)
SENSORS=$(find "$W1_DEVICES" -maxdepth 1 -type d -name "28-*")
if [ -z "$SENSORS" ]; then
    echo "No 1-wire sensors detected on GPIO${gpio_pin}."
else
    echo "1-wire sensor(s) detected on GPIO${gpio_pin}:"
    for sensor in $SENSORS; do
        SENSOR_ID=$(basename "$sensor")
        echo "  - Sensor ID: ${SENSOR_ID}"
    done
fi

echo "========== Script Completed =========="
echo "If you made changes to ${CONFIG_FILE}, please reboot your Raspberry Pi for them to take full effect."
