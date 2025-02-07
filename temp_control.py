#!/usr/bin/env python3
"""
temp_control.py v3.3
- Uses mqtt_handler.py for MQTT publishing.
- Uses web_ui.py for the Flask web interface.
- Detects a DS18B20 temperature sensor at startup:
    • If detected, uses live sensor data.
    • If not detected, falls back to simulated data.
- Inserts sensor data into MariaDB (for the web UI).
- Publishes sensor data via MQTT (for HomeAssistant).
"""

import logging
import threading
import time
import random
import glob
import os
import mysql.connector
import mqtt_handler  # For publishing MQTT messages and data_mode indicator
import web_ui        # To start the web interface

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/app.log"
handler = logging.handlers.RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Application starting... (v3.3)")

# ---------------------------
# Database Connection Settings
# ---------------------------
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'beerpi')
DB_DATABASE = os.environ.get('DB_DATABASE', 'beerpi_db')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')  # Ensure DB_PASSWORD is set in your environment

# ---------------------------
# Database Helper Functions
# ---------------------------
def create_sensor_table():
    """Creates the sensor_data table if it does not exist."""
    try:
        conn = mysql.connector.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_DATABASE)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sensor_data (
                id INT AUTO_INCREMENT PRIMARY KEY,
                temperature DECIMAL(5,2),
                relay_state VARCHAR(10),
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        logging.info("Sensor table ensured.")
    except Exception as e:
        logging.error("Failed to create sensor table: " + str(e))

def insert_sensor_data(temp, relay):
    """Inserts a sensor reading into the sensor_data table."""
    try:
        conn = mysql.connector.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_DATABASE)
        cursor = conn.cursor()
        query = "INSERT INTO sensor_data (temperature, relay_state, timestamp) VALUES (%s, %s, NOW())"
        cursor.execute(query, (temp, relay))
        conn.commit()
        cursor.close()
        conn.close()
        logging.info("Inserted sensor data into DB: Temp=%s, Relay=%s", temp, relay)
    except Exception as e:
        logging.error("Failed to insert sensor data into DB: " + str(e))

# Ensure the sensor_data table exists.
create_sensor_table()

# ---------------------------
# Temperature Sensor Detection Functions
# ---------------------------
def detect_temp_sensor():
    """
    Look for DS18B20 sensor directories in /sys/bus/w1/devices/.
    Returns the sensor directory if found, else None.
    """
    sensor_dirs = glob.glob('/sys/bus/w1/devices/28-*')
    if sensor_dirs:
        return sensor_dirs[0]
    return None

def read_temp_sensor(sensor_path):
    """
    Reads the temperature from the DS18B20 sensor.
    Returns the temperature in Celsius, or None on error.
    """
    try:
        with open(sensor_path + '/w1_slave', 'r') as f:
            lines = f.readlines()
        # Check for a valid reading.
        if lines[0].strip()[-3:] != "YES":
            logging.error("Temperature sensor not ready (CRC check failed).")
            return None
        equals_pos = lines[1].find("t=")
        if equals_pos != -1:
            temp_string = lines[1][equals_pos+2:]
            temp_c = float(temp_string) / 1000.0
            return temp_c
        else:
            logging.error("Temperature reading not found in sensor output.")
            return None
    except Exception as e:
        logging.error("Error reading temperature sensor: " + str(e))
        return None

# ---------------------------
# Detect Temperature Sensor and Set Data Mode
# ---------------------------
sensor_path = detect_temp_sensor()
if sensor_path:
    SIMULATE_SENSORS = False
    logging.info("Temperature sensor detected at: %s. Using live sensor data.", sensor_path)
    mqtt_handler.data_mode = "Live Data"
else:
    SIMULATE_SENSORS = True
    logging.warning("No temperature sensor detected. Using simulated data for all functions. "
                    "Please connect the sensor and restart the RaspberryPi to use live sensor data.")
    mqtt_handler.data_mode = "Simulated Data"

# ---------------------------
# Start Web UI in a Separate Thread
# ---------------------------
web_thread = threading.Thread(target=web_ui.start_web_ui)
web_thread.daemon = True
web_thread.start()
logging.info("Web UI started successfully.")

# ---------------------------
# Main Loop: Read Sensor Data, Insert into DB, and Publish via MQTT
# ---------------------------
while True:
    if SIMULATE_SENSORS:
        # Generate simulated data.
        temperature = round(random.uniform(18.0, 25.0), 2)
        relay_state = random.choice(["ON", "OFF"])
    else:
        # Read live sensor data.
        temperature = read_temp_sensor(sensor_path)
        # For relay state, if you have a physical relay or GPIO reading, add that logic.
        # Here we default to "OFF" when using live sensor data.
        relay_state = "OFF"
        if temperature is None:
            logging.error("Failed to read live sensor data; falling back to simulated data.")
            temperature = round(random.uniform(18.0, 25.0), 2)
            relay_state = random.choice(["ON", "OFF"])
    # Insert the reading into the MariaDB database.
    insert_sensor_data(temperature, relay_state)
    # Publish the data via MQTT for HomeAssistant.
    mqtt_handler.publish_message("home/beerpi/temperature", f"{temperature}")
    mqtt_handler.publish_message("home/beerpi/relay_state", relay_state)
    time.sleep(5)
