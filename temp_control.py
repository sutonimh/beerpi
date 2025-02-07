#!/usr/bin/env python3
"""
temp_control.py v2.6
- Uses `mqtt_handler.py` for MQTT functions.
- Keeps temperature monitoring and web UI separate from MQTT.
"""

import os
import logging
from flask import Flask, request, render_template
import threading
from logging.handlers import RotatingFileHandler
import mqtt_handler  # Import MQTT module

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
logging.info("Application starting... (v2.6)")

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    message = "System is running."
    
    # Example: Publish a message when someone loads the web page
    mqtt_handler.publish_message("home/beerpi/web_status", "Web UI Loaded", retain=False)

    return render_template("index.html", message=message)

if __name__ == "__main__":
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
