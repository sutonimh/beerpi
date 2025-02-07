#!/usr/bin/env python3
"""
BeerPi - Monitor DS18B20 temperature and relay state, publish via MQTT,
send data to InfluxDB, and support Home Assistant auto discovery.
"""

import os
import glob
import time
import json
import logging
from logging.handlers import RotatingFileHandler
import signal
import sys

# Import MQTT client
import paho.mqtt.client as mqtt

# Import InfluxDB client for InfluxDB 2.x
from influxdb_client import InfluxDBClient, Point, WritePrecision

# Try importing RPi.GPIO; if not available (for testing on non-RPi systems), simulate
try:
    import RPi.GPIO as GPIO
except ImportError:
    # Simulation for non-RPi environment
    class GPIO:
        BCM = BOARD = OUT = IN = None
        @staticmethod
        def setmode(mode): pass
        @staticmethod
        def setup(pin, mode): pass
        @staticmethod
        def output(pin, value): pass
        @staticmethod
        def input(pin):
            # Simulate a relay off (0) by default
            return 0
        @staticmethod
        def cleanup(): pass

# Read configuration values from environment variables.
# These values are set in the installation script and loaded from ~/.beerpi_install_config.
MQTT_BROKER_HOST       = os.environ.get("MQTT_BROKER_HOST", "localhost")
MQTT_BROKER_PORT       = int(os.environ.get("MQTT_BROKER_PORT", "1883"))
MQTT_TOPIC_TEMPERATURE = os.environ.get("MQTT_TOPIC_TEMPERATURE", "beerpi/temperature")
MQTT_TOPIC_RELAY       = os.environ.get("MQTT_TOPIC_RELAY", "beerpi/relay")

INFLUX_URL    = os.environ.get("INFLUX_URL", "http://localhost:8086")
INFLUX_ORG    = os.environ.get("INFLUX_ORG", "beerpi")
INFLUX_BUCKET = os.environ.get("INFLUX_BUCKET", "beerpi")
INFLUX_TOKEN  = os.environ.get("INFLUX_TOKEN", "")

# Poll interval in seconds (default 5 seconds)
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "5"))

# GPIO pin for relay (default 27)
GPIO_RELAY_PIN = int(os.environ.get("GPIO_RELAY_PIN", "27"))

# Log file configuration
LOG_FILE = os.environ.get("LOG_FILE", "/var/log/beerpi.log")
LOG_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
LOG_BACKUP_COUNT = 7

# Set up logging with a rotating file handler.
logger = logging.getLogger("BeerPi")
logger.setLevel(logging.INFO)
handler = RotatingFileHandler(LOG_FILE, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

# Set up InfluxDB client
influx_client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
write_api = influx_client.write_api(write_options=WritePrecision.S)

# Set up MQTT client
mqtt_client = mqtt.Client()
mqtt_client.connect(MQTT_BROKER_HOST, MQTT_BROKER_PORT, 60)

def publish_homeassistant_discovery():
    """Publish Home Assistant MQTT auto discovery messages for temperature and relay."""
    # Temperature sensor discovery message
    temp_config_topic = "homeassistant/sensor/beerpi_temperature/config"
    temp_config_payload = {
        "name": "BeerPi Temperature",
        "state_topic": MQTT_TOPIC_TEMPERATURE,
        "unit_of_measurement": "°C",
        "device_class": "temperature",
        "unique_id": "beerpi_temperature",
        "value_template": "{{ value_json.temperature }}"
    }
    mqtt_client.publish(temp_config_topic, json.dumps(temp_config_payload))
    logger.info("Published Home Assistant auto discovery for temperature sensor.")

    # Relay state discovery message (as a binary sensor)
    relay_config_topic = "homeassistant/binary_sensor/beerpi_relay/config"
    relay_config_payload = {
        "name": "BeerPi Relay",
        "state_topic": MQTT_TOPIC_RELAY,
        "payload_on": "ON",
        "payload_off": "OFF",
        "device_class": "power",
        "unique_id": "beerpi_relay",
        "value_template": "{{ value_json.relay }}"
    }
    mqtt_client.publish(relay_config_topic, json.dumps(relay_config_payload))
    logger.info("Published Home Assistant auto discovery for relay state.")

def read_temperature():
    """
    Read temperature from the DS18B20 sensor.
    The sensor data is available under /sys/bus/w1/devices/28-*/w1_slave.
    """
    try:
        # Find the sensor file; assume only one sensor is connected.
        sensor_files = glob.glob("/sys/bus/w1/devices/28-*/w1_slave")
        if not sensor_files:
            logger.error("No DS18B20 sensor found!")
            return None
        sensor_file = sensor_files[0]
        with open(sensor_file, "r") as f:
            lines = f.readlines()
        # Check for a successful reading
        if lines[0].strip()[-3:] != "YES":
            logger.error("Temperature sensor not ready.")
            return None
        # Parse temperature from second line
        equals_pos = lines[1].find("t=")
        if equals_pos != -1:
            temp_string = lines[1][equals_pos + 2:]
            temperature = float(temp_string) / 1000.0
            return temperature
    except Exception as e:
        logger.exception("Error reading temperature: %s", e)
        return None

def read_relay_state():
    """
    Read the current state of the relay.
    The relay is assumed to be controlled by a GPIO output.
    """
    try:
        # Read the GPIO output state; assume HIGH means ON.
        state = GPIO.input(GPIO_RELAY_PIN)
        return "ON" if state else "OFF"
    except Exception as e:
        logger.exception("Error reading relay state: %s", e)
        return "UNKNOWN"

def send_data(temperature, relay_state):
    """Publish sensor data via MQTT and write the data point to InfluxDB."""
    # Publish MQTT messages
    temp_payload = json.dumps({"temperature": temperature})
    relay_payload = json.dumps({"relay": relay_state})
    mqtt_client.publish(MQTT_TOPIC_TEMPERATURE, temp_payload)
    mqtt_client.publish(MQTT_TOPIC_RELAY, relay_payload)
    logger.info("Published MQTT messages: %s, %s", temp_payload, relay_payload)

    # Write data point to InfluxDB
    point = (
        Point("beerpi")
        .field("temperature", temperature if temperature is not None else 0.0)
        .field("relay", 1 if relay_state == "ON" else 0)
    )
    try:
        write_api.write(bucket=INFLUX_BUCKET, org=INFLUX_ORG, record=point)
        logger.info("Wrote data to InfluxDB: %s", point.to_line_protocol())
    except Exception as e:
        logger.exception("Error writing to InfluxDB: %s", e)

def cleanup(signum, frame):
    """Cleanup function for graceful exit."""
    logger.info("Shutting down BeerPi...")
    GPIO.cleanup()
    mqtt_client.disconnect()
    sys.exit(0)

def main():
    # Setup GPIO mode and relay pin
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(GPIO_RELAY_PIN, GPIO.OUT)
    # (If needed, you can initialize the relay output state here.)

    # Publish Home Assistant auto discovery messages on startup.
    publish_homeassistant_discovery()

    # Register signal handlers for graceful shutdown.
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    logger.info("Starting BeerPi loop with a %s second interval.", POLL_INTERVAL)
    while True:
        temperature = read_temperature()
        relay_state = read_relay_state()
        logger.info("Temperature: %s °C, Relay: %s", temperature, relay_state)
        send_data(temperature, relay_state)
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
