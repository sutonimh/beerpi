#!/bin/bash
# influx.sh
# This script removes any existing InfluxDB installation and data, then installs InfluxDB on a Raspberry Pi using a prebuilt ARM package.
# It sets up two databases ("sensor_db" and "combined_sensor_db"), drops any preexisting continuous queries,
# and creates new continuous queries that merge the latest sensor (or simulated) temperature data into the "temperature"
# measurement in the "combined_sensor_db" database.
#
# Finally, it enters an endless loop to read temperature data from a DS18B20 sensor on the 1-wire interface
# (or generate simulated data if no sensor is found) and writes it into the "sensor_db" database.
#
# WARNING: This script will purge any existing InfluxDB installation and delete all InfluxDB data.
#
set -e

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Please run with sudo."
    exit 1
fi

########################################
# Clean slate: Remove any previous InfluxDB installation and data.
########################################
echo "Cleaning previous InfluxDB installation..."
if dpkg -l | grep -q influxdb; then
    systemctl stop influxdb || true
    dpkg --purge influxdb || true
fi
rm -rf /var/lib/influxdb
rm -rf /etc/influxdb

########################################
# Install InfluxDB via prebuilt ARM package.
########################################
echo "Installing InfluxDB..."
wget -qO influxdb.deb https://dl.influxdata.com/influxdb/releases/influxdb_1.8.10_armhf.deb
dpkg -i influxdb.deb
rm influxdb.deb
systemctl enable influxdb
systemctl start influxdb
echo "InfluxDB installed and started."

########################################
# Clean slate: Drop existing databases if they exist.
########################################
echo "Dropping existing databases if any..."
influx -execute "DROP DATABASE sensor_db" || true
influx -execute "DROP DATABASE combined_sensor_db" || true

########################################
# Create the sensor_db and combined_sensor_db databases.
########################################
echo "Creating InfluxDB database 'sensor_db'..."
influx -execute "CREATE DATABASE sensor_db" >/dev/null 2>&1
echo "Database 'sensor_db' created."
echo "Creating InfluxDB database 'combined_sensor_db'..."
influx -execute "CREATE DATABASE combined_sensor_db" >/dev/null 2>&1
echo "Database 'combined_sensor_db' created."

########################################
# Drop any existing continuous queries.
########################################
echo "Dropping any existing continuous queries..."
influx -execute "DROP CONTINUOUS QUERY cq_real ON sensor_db" || true
influx -execute "DROP CONTINUOUS QUERY cq_simulated ON sensor_db" || true

########################################
# Create continuous queries to merge sensor data.
########################################
echo "Creating continuous queries to merge sensor data..."
influx -execute "CREATE CONTINUOUS QUERY cq_real ON sensor_db BEGIN SELECT last(temperature) as temperature INTO combined_sensor_db.autogen.temperature FROM real_data GROUP BY time(10s) END" >/dev/null 2>&1
influx -execute "CREATE CONTINUOUS QUERY cq_simulated ON sensor_db BEGIN SELECT last(temperature) as temperature INTO combined_sensor_db.autogen.temperature FROM simulated_data GROUP BY time(10s) END" >/dev/null 2>&1
echo "Continuous queries created."

########################################
# Sensor data collection loop.
########################################
SENSOR_BASE_DIR="/sys/bus/w1/devices"
SLEEP_INTERVAL=10

echo "========== Starting sensor data collection loop =========="
while true; do
    # Look for a DS18B20 sensor (directories starting with "28-")
    SENSOR_DIR=$(find "$SENSOR_BASE_DIR" -maxdepth 1 -type d -name "28-*")
    if [ -n "$SENSOR_DIR" ]; then
        SENSOR_FILE="${SENSOR_DIR}/w1_slave"
        if [ -f "$SENSOR_FILE" ]; then
            echo "[INFO] Real sensor detected at ${SENSOR_DIR}."
            TEMP_RAW=$(grep "t=" "$SENSOR_FILE" | awk -F 't=' '{print $2}')
            TEMP=$(echo "scale=2; $TEMP_RAW/1000" | bc)
            echo "[DATA] Sensor temperature: ${TEMP} °C"
            MEASUREMENT="real_data"
            DATA="temperature=${TEMP}"
        else
            echo "[WARN] Sensor directory found but sensor file missing. Using simulated data."
            MEASUREMENT="simulated_data"
            TEMP=$(awk -v min=20 -v max=30 'BEGIN{srand(); print min+rand()*(max-min)}')
            echo "[DATA] Simulated temperature: ${TEMP} °C"
            DATA="temperature=${TEMP}"
        fi
    else
        echo "[INFO] No real sensor detected. Using simulated data."
        MEASUREMENT="simulated_data"
        TEMP=$(awk -v min=20 -v max=30 'BEGIN{srand(); print min+rand()*(max-min)}')
        echo "[DATA] Simulated temperature: ${TEMP} °C"
        DATA="temperature=${TEMP}"
    fi

    echo "[INFO] Writing data to InfluxDB measurement '${MEASUREMENT}' in database 'sensor_db'..."
    curl -s -XPOST "http://localhost:8086/write?db=sensor_db" --data-binary "${MEASUREMENT} ${DATA}"
    echo "[INFO] Data write complete."
    
    echo "Sleeping for ${SLEEP_INTERVAL} seconds before next reading..."
    sleep ${SLEEP_INTERVAL}
done
