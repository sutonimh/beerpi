#!/usr/bin/env python3
"""
web_ui.py v1.3
Handles the Flask web interface for BeerPi.
- Retrieves sensor data from the MariaDB database.
- Displays the most recent sensor reading and, optionally, historical graph data.
- Shows a data mode indicator below the graph card:
    • "Simulated Data" in red when no sensor is connected.
    • "Live Data" in green when live sensor data is available.
"""

import os
import logging
from flask import Flask, render_template, jsonify
import mysql.connector
from logging.handlers import RotatingFileHandler
import mqtt_handler  # Used for the data_mode indicator

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
logging.info("Web UI starting... (v1.3)")

# ---------------------------
# Database Connection Settings
# ---------------------------
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'beerpi')
DB_DATABASE = os.environ.get('DB_DATABASE', 'beerpi_db')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')

# ---------------------------
# Helper Function to Retrieve Latest Sensor Data
# ---------------------------
def get_latest_sensor_data():
    """Queries the database for the latest sensor reading."""
    try:
        conn = mysql.connector.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_DATABASE)
        cursor = conn.cursor()
        cursor.execute("SELECT temperature, relay_state, timestamp FROM sensor_data ORDER BY timestamp DESC LIMIT 1")
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row:
            return {"temperature": row[0], "relay_state": row[1], "timestamp": row[2]}
        else:
            return {"temperature": None, "relay_state": "Unknown", "timestamp": None}
    except Exception as e:
        logging.error("Failed to retrieve sensor data: " + str(e))
        return {"temperature": None, "relay_state": "Error", "timestamp": None}

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    message = "System is running."
    sensor_data = get_latest_sensor_data()
    # Get the data mode from mqtt_handler (set by temp_control.py)
    data_mode = getattr(mqtt_handler, "data_mode", "Unknown")
    return render_template("index.html",
                           message=message,
                           sensor_data=sensor_data,
                           data_mode=data_mode)

@app.route("/data", methods=["GET"])
def data():
    """Endpoint to fetch the latest sensor data as JSON."""
    sensor_data = get_latest_sensor_data()
    data_mode = getattr(mqtt_handler, "data_mode", "Unknown")
    return jsonify({
        "sensor_data": sensor_data,
        "data_mode": data_mode
    })

def start_web_ui():
    """Starts the Flask web interface."""
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
