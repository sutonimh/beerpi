#!/usr/bin/env python3
"""
web_ui.py v1.0
Handles the Flask web interface for BeerPi.
- Initializes and runs the Flask app.
- Provides UI for temperature monitoring and relay control.
"""

import logging
from flask import Flask, request, render_template
from logging.handlers import RotatingFileHandler
import mqtt_handler  # Import MQTT for publishing messages

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/web_ui.log"
handler = RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger("WebUI")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Web UI starting... (v1.0)")

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

# Default values
current_relay_state = "Unknown"

@app.route("/", methods=["GET", "POST"])
def index():
    global current_relay_state
    message = "System is running."

    # Example: Publish a message when someone loads the web page
    mqtt_handler.publish_message("home/beerpi/web_status", "Web UI Loaded", retain=False)

    return render_template("index.html", message=message, current_relay_state=current_relay_state)

def start_web_ui():
    """ Starts the Flask web interface. """
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)

