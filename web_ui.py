#!/usr/bin/env python3
"""
web_ui.py v1.1
Handles the Flask web interface for BeerPi.
- Initializes and runs the Flask app.
- Provides UI for temperature monitoring and relay control.
- Displays simulated sensor data from MQTT.
"""

import logging
from flask import Flask, render_template, jsonify
import mqtt_handler  # Import MQTT for accessing sensor data and publishing messages

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/web_ui.log"
handler = logging.handlers.RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger("WebUI")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Web UI starting... (v1.1)")

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    message = "System is running."
    # Notify via MQTT that the web UI was loaded
    mqtt_handler.publish_message("home/beerpi/web_status", "Web UI Loaded", retain=False)
    # Retrieve the latest simulated sensor data from mqtt_handler globals
    current_relay_state = mqtt_handler.current_relay_state
    current_temperature = mqtt_handler.current_temperature
    return render_template("index.html",
                           message=message,
                           current_relay_state=current_relay_state,
                           current_temperature=current_temperature)

@app.route("/data", methods=["GET"])
def data():
    # Endpoint to fetch the latest sensor data as JSON (for dynamic UI updates)
    return jsonify({
        "current_relay_state": mqtt_handler.current_relay_state,
        "current_temperature": mqtt_handler.current_temperature
    })

def start_web_ui():
    """Starts the Flask web interface."""
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
