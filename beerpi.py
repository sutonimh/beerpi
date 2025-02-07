#!/usr/bin/env python3
"""
beerpi.py - BeerPi Project

This script does the following:
  • Reads temperature from a DS18B20 sensor attached via the Raspberry Pi’s 1-Wire interface.
  • Reads (or simulates) the relay state from a designated GPIO pin.
  • Writes the temperature and relay state into InfluxDB.
  • Publishes the sensor values via MQTT for Home Assistant integration.

Requirements:
  - Enable 1-Wire on your Raspberry Pi (typically via /boot/config.txt and dtoverlay=w1-gpio).
  - The DS18B20 sensor should appear under /sys/bus/w1/devices/28-*.
  - Python packages: paho-mqtt, influxdb-client, and (optionally) RPi.GPIO.
    Install with: pip install paho-mqtt influxdb-client RPi.GPIO

Configuration:
  - All credentials and connection settings (for MQTT and InfluxDB) are read from environment variables.
    Alternatively, you can hardcode them below.

MQTT is used only to publish data for Home Assistant.
Sensor data comes directly from the physical DS18B20 sensor.
"""

import os
import time
import glob
import logging
import paho.mqtt.client as mqtt
from influxdb_client import InfluxDBClient, Point, WritePrecision

# Attempt to import RPi.GPIO for relay state reading; if not available, we'll simulate.
try:
    import RPi.GPIO as GPIO
    GPIO_AVAILABLE = True
except ImportError:
    GPIO_AVAILABLE = False

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")

# ----- Configuration Settings -----
# MQTT settings (used to publish to Home Assistant)
MQTT_BROKER   = os.environ.get("MQTT_BROKER", "192.168.5.12")
MQTT_PORT     = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USERNAME = os.environ.get("MQTT_USERNAME", "ha_mqtt")
MQTT_PASSWORD = os.environ.get("MQTT_PASSWORD", "your_mqtt_password")

# InfluxDB settings (for InfluxDB 2.x)
INFLUX_URL    = os.environ.get("INFLUX_URL", "http://localhost:8086")
INFLUX_TOKEN  = os.environ.get("INFLUX_TOKEN", "your_influx_token")
INFLUX_ORG    = os.environ.get("INFLUX_ORG", "your_org")
INFLUX_BUCKET = os.environ.get("INFLUX_BUCKET", "beerpi")

# DS18B20 sensor detection: sensor directories begin with "28-"
def detect_temp_sensor():
    sensor_dirs = glob.glob('/sys/bus/w1/devices/28-*')
    if sensor_dirs:
        return sensor_dirs[0]
    else:
        return None

def read_temp_sensor(sensor_path):
    try:
        with open(sensor_path + '/w1_slave', 'r') as f:
            lines = f.readlines()
        # Check for valid sensor output (CRC check)
        if lines[0].strip()[-3:] != "YES":
            logging.error("Temperature sensor not ready (CRC check failed).")
            return None
        equals_pos = lines[1].find("t=")
        if equals_pos != -1:
            temp_string = lines[1][equals_pos+2:]
            return float(temp_string) / 1000.0
        else:
            logging.error("Temperature reading not found in sensor data.")
            return None
    except Exception as e:
        logging.error("Error reading temperature sensor: %s", e)
        return None

# Relay state: if GPIO is available, use a designated input pin; otherwise, simulate.
# Change RELAY_PIN as needed.
RELAY_PIN = 17

def setup_relay():
    if GPIO_AVAILABLE:
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(RELAY_PIN, GPIO.IN)  # Assumes relay state is provided as digital input
    else:
        logging.info("RPi.GPIO not available. Relay state will be simulated.")

def read_relay_state():
    if GPIO_AVAILABLE:
        # Assume HIGH means ON, LOW means OFF
        state = GPIO.input(RELAY_PIN)
        return "ON" if state == GPIO.HIGH else "OFF"
    else:
        # Simulate relay state if not using GPIO
        import random
        return random.choice(["ON", "OFF"])

# ----- Initialize InfluxDB Client -----
influx_client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
write_api = influx_client.write_api(write_options=WritePrecision.NS)

# ----- Initialize MQTT Client for Publishing -----
mqtt_client = mqtt.Client("beerpi_publisher")
mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_start()

def publish_to_mqtt(temperature, relay_state):
    # Publish temperature and relay state to respective MQTT topics
    mqtt_client.publish("home/beerpi/temperature", payload=str(temperature), retain=False)
    mqtt_client.publish("home/beerpi/relay_state", payload=relay_state, retain=False)
    logging.info("Published to MQTT: temperature=%s, relay_state=%s", temperature, relay_state)

def write_to_influx(temperature, relay_state):
    # Write a point for temperature
    point_temp = Point("temperature").field("value", temperature).time(time.time_ns(), WritePrecision.NS)
    write_api.write(bucket=INFLUX_BUCKET, record=point_temp)
    # Write a point for relay state
    point_relay = Point("relay_state").tag("state", relay_state).time(time.time_ns(), WritePrecision.NS)
    write_api.write(bucket=INFLUX_BUCKET, record=point_relay)
    logging.info("Wrote to InfluxDB: temperature=%s, relay_state=%s", temperature, relay_state)

def main():
    sensor_path = detect_temp_sensor()
    if sensor_path:
        logging.info("DS18B20 sensor detected at %s", sensor_path)
    else:
        logging.error("No DS18B20 temperature sensor detected on GPIO. Exiting.")
        return

    setup_relay()

    # Main loop: read sensor data, write to InfluxDB, and publish to MQTT every 10 seconds.
    while True:
        temperature = read_temp_sensor(sensor_path)
        if temperature is None:
            logging.error("Failed to read temperature. Skipping this cycle.")
        else:
            relay_state = read_relay_state()
            logging.info("Read temperature=%.2f°C and relay_state=%s", temperature, relay_state)
            write_to_influx(temperature, relay_state)
            publish_to_mqtt(temperature, relay_state)
        time.sleep(10)

if __name__ == "__main__":
    main()
