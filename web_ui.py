#!/usr/bin/env python3
"""
web_ui.py v1.8 (revised)
Handles the Flask web interface for BeerPi.
- Retrieves sensor data from the MariaDB database.
- Generates a Plotly graph from historical sensor data.
- Supplies template variables expected by your index.html.
"""

import os
import logging
from flask import Flask, render_template, request, jsonify
import mysql.connector
from logging.handlers import RotatingFileHandler
import mqtt_handler  # Used here for consistency

# Import Plotly modules
import plotly.graph_objs as go
from plotly.offline import plot

def get_db_password():
    """
    Attempts to retrieve DB_PASSWORD.
    First, it checks the environment.
    If not set, it reads the configuration file (~/.beerpi_install_config)
    and parses it into a dictionary.
    """
    db_password = os.environ.get("DB_PASSWORD")
    if db_password:
        return db_password
    config_path = os.path.expanduser("~/.beerpi_install_config")
    try:
        with open(config_path, "r") as f:
            lines = f.readlines()
        config = {}
        for line in lines:
            if "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip().strip('"')
        return config.get("DB_PASSWORD", "")
    except Exception as e:
        logging.error("Failed to read DB_PASSWORD from config: " + str(e))
    return ""

# ---------------------------
# Database Connection Settings
# ---------------------------
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_USER = os.environ.get("DB_USER", "beerpi")
DB_DATABASE = os.environ.get("DB_DATABASE", "beerpi_db")
DB_PASSWORD = get_db_password()

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
logging.info("Web UI starting... (v1.8 revised)")

# ---------------------------
# Helper Function: Retrieve Latest Sensor Data
# ---------------------------
def get_latest_sensor_data():
    """
    Queries the MariaDB database for the latest sensor reading.
    Returns a dictionary with keys: temperature, relay_state, and timestamp.
    """
    try:
        conn = mysql.connector.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_DATABASE
        )
        cursor = conn.cursor()
        cursor.execute("SELECT temperature, relay_state, timestamp FROM sensor_data ORDER BY timestamp DESC LIMIT 1")
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row:
            return {"temperature": row[0], "relay_state": row[1], "timestamp": row[2]}
        else:
            return {"temperature": None, "relay_state": "ERROR", "timestamp": None}
    except Exception as e:
        logging.error("Failed to retrieve sensor data: " + str(e))
        return {"temperature": None, "relay_state": "ERROR", "timestamp": None}

# ---------------------------
# Helper Function: Generate Historical Data Graph
# ---------------------------
def get_historical_sensor_graph():
    """
    Queries the last 50 sensor readings from the database and generates a Plotly graph.
    Returns the HTML div string for embedding the graph.
    """
    try:
        conn = mysql.connector.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_DATABASE
        )
        cursor = conn.cursor()
        cursor.execute("SELECT temperature, timestamp FROM sensor_data ORDER BY timestamp DESC LIMIT 50")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        if not rows:
            return "<div>No data available for graph.</div>"
        # Reverse rows so that data is in ascending order by timestamp
        rows = rows[::-1]
        x_values = [row[1] for row in rows]
        y_values = [row[0] for row in rows]
        trace = go.Scatter(x=x_values, y=y_values, mode='lines+markers', name='Temperature')
        layout = go.Layout(
            title='Temperature Over Time',
            xaxis={'title': 'Timestamp'},
            yaxis={'title': 'Temperature (°C)'},
            paper_bgcolor='#1e1e1e',
            plot_bgcolor='#1e1e1e',
            font=dict(color='#e0e0e0')
        )
        fig = go.Figure(data=[trace], layout=layout)
        graph_div = plot(fig, output_type='div', include_plotlyjs=False)
        return graph_div
    except Exception as e:
        logging.error("Failed to generate graph: " + repr(e))
        return f"<div>Error generating graph: {str(e)}</div>"

# ---------------------------
# Flask Web Application Setup
# ---------------------------
app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def index():
    message = "System is running."
    sensor_data = get_latest_sensor_data()
    current_relay_state = sensor_data.get("relay_state", "ERROR")
    graph_div = get_historical_sensor_graph()
    min_temp = 18.0
    max_temp = 25.0
    view_hours = 24
    manual_control = False
    return render_template("index.html",
                           message=message,
                           graph_div=graph_div,
                           min_temp=min_temp,
                           max_temp=max_temp,
                           view_hours=view_hours,
                           manual_control=manual_control,
                           current_relay_state=current_relay_state)

@app.route("/data", methods=["GET"])
def data():
    sensor_data = get_latest_sensor_data()
    return jsonify(sensor_data)

def start_web_ui():
    logging.info("Starting Flask app on port 5000")
    app.run(host="0.0.0.0", port=5000, debug=False)

if __name__ == "__main__":
    start_web_ui()
