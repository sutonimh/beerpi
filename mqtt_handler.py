#!/usr/bin/env python3
"""
mqtt_handler.py v1.2
Handles all MQTT-related operations for BeerPi.
- Publishes sensor data for use in HomeAssistant.
- Minimal subscription functionality is retained (for configuration, etc.).
- Maintains a global variable 'data_mode' indicating "Live Data" or "Simulated Data".
"""

import os
import time
import logging
import paho.mqtt.client as mqtt
from logging.handlers import RotatingFileHandler

# Global variable to indicate the current data mode.
data_mode = "Unknown"

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/mqtt.log"
handler = RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger("MQTT")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("MQTT Handler starting... (v1.2)")

# ---------------------------
# MQTT Configuration
# ---------------------------
MQTT_BROKER = os.getenv('MQTT_BROKER', '192.168.5.12')
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
MQTT_USERNAME = os.getenv('MQTT_USERNAME', 'ha_mqtt')
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD', 'stuffNthings')

mqtt_client = mqtt.Client(client_id="beerpi", clean_session=False)
if MQTT_USERNAME and MQTT_PASSWORD:
    mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logging.info("Connected to MQTT broker at %s:%s", MQTT_BROKER, MQTT_PORT)
        client.publish("home/beerpi/status", "online", retain=True)
        # Subscribe to configuration topics if needed.
        client.subscribe("home/beerpi/config/#")
    else:
        logging.error("Failed to connect to MQTT broker, return code %s", rc)

def on_message(client, userdata, msg):
    # Minimal processing: simply log any incoming messages.
    logging.info("Received MQTT message: %s -> %s", msg.topic, msg.payload.decode())

mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

max_retries = 5
retry_delay = 5  # seconds

for attempt in range(max_retries):
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=120)
        mqtt_client.loop_start()
        break
    except Exception as e:
        logging.error("MQTT Connection Failed (%s/%s): %s", attempt+1, max_retries, e)
        if attempt < max_retries - 1:
            time.sleep(retry_delay)
        else:
            logging.critical("Failed to connect to MQTT after multiple attempts. Continuing without MQTT.")

def publish_message(topic, message, retain=False):
    """Publishes a message to an MQTT topic."""
    try:
        mqtt_client.publish(topic, message, retain=retain)
        logging.info("Published to %s: %s", topic, message)
    except Exception as e:
        logging.error("Failed to publish message to %s: %s", topic, e)
