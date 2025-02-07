#!/usr/bin/env python3
"""
web_ui.py v1.4
Handles the Flask web interface for BeerPi.
- Retrieves sensor data from the MariaDB database.
- Supplies variables expected by the provided index.html template.
  Expected template variables:
    • graph_div: HTML for the graph (placeholder if none available)
    • min_temp: default minimum temperature (e.g. 18.0)
    • max_temp: default maximum temperature (e.g. 25.0)
    • view_hours: default view period in hours (e.g. 24)
    • manual_control: Boolean indicating if manual relay control is enabled
    • current_relay_state: The latest relay state (string)
    • message: A status message (string)
"""

import os
import logging
from flask import Flask, render_template, request, jsonify
import mysql.connector
from logging.handlers import RotatingFileHandler
import mqtt_handler  # (For potential future use, e.g., data mode indicator)

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/web_ui.log"
handler = RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter(
    "%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
)
handler.setFormatter(formatter)
logger = logging.getLogger("WebUI")
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Web UI starting... (v1.4)")

# ---------------------------
# Database Connection Settings
# ---------------------------
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_USER = os.environ.get("DB_USER", "beerpi")
DB_DATABASE = os.environ.get("DB_DATABASE", "beerpi_db")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

# ---------------------------
# Helper Function to Retrieve Latest Sensor Data
# ---------------------------
def get_latest_sensor_data():
    """
    Queries the MariaDB database for the latest sensor reading.
    Returns a dictionary with keys: temperature, relay_state, and timestamp.
    """
    try:
        conn = mysql.connector.connect(
            host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_DATABASE
        )
        cursor = conn.cursor()
        cursor.execute(
            "SELECT temperature, relay_state, timestamp FROM sensor_data ORDER BY timestamp DESC LIMIT 1"
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row:
            return {"temperature": row[0], "relay_state": row[1], "timestamp": row[2]}
        else:
            return {"temperature": None, "relay_state": "unknown", "timestamp": None}
    except Exception as e:
        logging.error("Failed to retrieve sensor data: " + str(e))
        return {"temperature": None, "relay_state": "error", "timestamp": None}

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    message = "System is running."
    sensor_data = get_latest_sensor_data()
    # Use the relay state from the database (or default to "unknown")
    current_relay_state = sensor_data.get("relay_state", "unknown")
    # For the graph, use a placeholder (replace with actual Plotly graph HTML if available)
    graph_div = "<div id='graph'>[Graph Placeholder]</div>"
    # Default settings (these could be made configurable if needed)
    min_temp = 18.0
    max_temp = 25.0
    view_hours = 24
    manual_control = False  # Set to True if manual control is enabled
    return render_template(
        "index.html",
        message=message,
        graph_div=graph_div,
        min_temp=min_temp,
        max_temp=max_temp,
        view_hours=view_hours,
        manual_control=manual_control,
        current_relay_state=current_relay_state,
    )

@app.route("/data", methods=["GET"])
def data():
    """Optional endpoint to return the latest sensor data as JSON."""
    sensor_data = get_latest_sensor_data()
    return jsonify(sensor_data)

def start_web_ui():
    """Starts the Flask web interface on port 5000."""
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)

if __name__ == "__main__":
    start_web_ui()
