#!/usr/bin/env python3
"""
mqtt_handler.py v1.1
Handles all MQTT-related operations for BeerPi.
- Manages connection with retry logic.
- Handles message subscriptions and publishing.
- Updates global variables for simulated sensor data.
"""

import os
import time
import logging
import paho.mqtt.client as mqtt
from logging.handlers import RotatingFileHandler

# Global variables to store sensor data
current_temperature = None
current_relay_state = "Unknown"

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
logging.info("MQTT Handler starting... (v1.1)")

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

# ---------------------------
# MQTT Callbacks
# ---------------------------
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logging.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
        client.publish("home/beerpi/status", "online", retain=True)
        # Subscribe to configuration updates and sensor topics
        client.subscribe("home/beerpi/config/#")
        client.subscribe("home/beerpi/temperature")
        client.subscribe("home/beerpi/relay_state")
    else:
        logging.error(f"Failed to connect to MQTT broker, return code {rc}")

def on_message(client, userdata, msg):
    global current_temperature, current_relay_state
    payload = msg.payload.decode()
    logging.info(f"Received MQTT message: {msg.topic} -> {payload}")
    # Update global variables based on topic
    if msg.topic == "home/beerpi/temperature":
        current_temperature = payload
    elif msg.topic == "home/beerpi/relay_state":
        current_relay_state = payload

# Assign callbacks
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

# ---------------------------
# MQTT Connection with Retry Logic
# ---------------------------
max_retries = 5
retry_delay = 5  # seconds

for attempt in range(max_retries):
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=120)
        mqtt_client.loop_start()
        break
    except Exception as e:
        logging.error(f"MQTT Connection Failed ({attempt+1}/{max_retries}): {e}")
        if attempt < max_retries - 1:
            time.sleep(retry_delay)
        else:
            logging.critical("Failed to connect to MQTT after multiple attempts. Continuing without MQTT.")

# ---------------------------
# Helper Function to Publish Messages
# ---------------------------
def publish_message(topic, message, retain=False):
    """Publishes a message to an MQTT topic."""
    try:
        mqtt_client.publish(topic, message, retain=retain)
        logging.info(f"Published to {topic}: {message}")
    except Exception as e:
        logging.error(f"Failed to publish message to {topic}: {e}")
