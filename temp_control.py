#!/usr/bin/env python3
"""
temp_control.py v3.1
- Uses `mqtt_handler.py` for MQTT functions.
- Uses `web_ui.py` for the Flask web interface.
- Simulates sensor data (temperature and relay state) for testing when no physical sensors are connected.
"""

import logging
import threading
import time
import random
import mqtt_handler  # Import MQTT module
import web_ui        # Import Web UI module

# ---------------------------
# Logging Configuration
# ---------------------------
log_file = "/home/tempmonitor/temperature_monitor/app.log"
handler = logging.handlers.RotatingFileHandler(log_file, maxBytes=5*1024*1024, backupCount=5)
formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)
logging.info("Application starting... (v3.1)")

# ---------------------------
# Start Web UI in a Separate Thread
# ---------------------------
web_thread = threading.Thread(target=web_ui.start_web_ui)
web_thread.daemon = True
web_thread.start()
logging.info("Web UI started successfully.")

# ---------------------------
# Simulation Loop
# ---------------------------
SIMULATE_SENSORS = True

while True:
    if SIMULATE_SENSORS:
        # Simulate a temperature reading between 18°C and 25°C
        simulated_temp = round(random.uniform(18.0, 25.0), 2)
        # Simulate relay state as either "ON" or "OFF"
        simulated_relay = random.choice(["ON", "OFF"])
        # Publish simulated data via MQTT
        mqtt_handler.publish_message("home/beerpi/temperature", f"{simulated_temp}")
        mqtt_handler.publish_message("home/beerpi/relay_state", simulated_relay)
        logging.info(f"Simulated data published: Temperature={simulated_temp}, Relay={simulated_relay}")
    time.sleep(5)
