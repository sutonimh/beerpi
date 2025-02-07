#!/usr/bin/env python3
"""
temp_control.py v3.0
- Uses `mqtt_handler.py` for MQTT functions.
- Uses `web_ui.py` for the Flask web interface.
- Keeps main script clean and modular.
"""

import logging
import threading
from logging.handlers import RotatingFileHandler
import mqtt_handler  # Import MQTT module
import web_ui  # Import Web UI module

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
logging.info("Application starting... (v3.0)")

# ---------------------------
# Start Web UI in a Separate Thread
# ---------------------------
web_thread = threading.Thread(target=web_ui.start_web_ui)
web_thread.daemon = True
web_thread.start()

logging.info("Web UI started successfully.")

# ---------------------------
# Keep the script running
# ---------------------------
while True:
    pass  # Main loop placeholder
