# BeerPi v2 Backend

BeerPi v2 is a backend system for monitoring and controlling beer fermentation. It provides real-time monitoring through MQTT, a REST API for configuration and data retrieval, and WebSocket support for live updates. The system also integrates with Home Assistant via MQTT discovery.

## Features

- **Configuration Management:**  
  Loads configuration settings from a YAML file (`/opt/beerpi/config/config.yaml`).

- **Database Integration:**  
  Connects to PostgreSQL to store temperature logs and relay state updates.

- **Logging:**  
  Uses rotating log files to record system events (located in `/var/log/beerpi`).

- **MQTT Integration:**  
  - Publishes discovery messages to Home Assistant.
  - Publishes sensor data (temperature and relay state) to designated topics.
  - Subscribes to control commands to update relay state.

- **REST API Endpoints:**  
  Provides endpoints to test the database, retrieve system version, fetch current relay state, view historical temperature logs, and get/update system settings.

- **WebSocket Integration:**  
  Uses Flask-SocketIO for real-time updates (temperature and relay state) to connected clients.

- **Automated Relay Control:**  
  Implements relay control logic based on temperature thresholds.  
  Supports dynamic switching between simulated sensor data and real sensor readings (DS18B20) via a runtime configuration.

- **Dynamic Sensor Mode:**  
  A global `sensor_config` allows switching between `"simulated"` and `"real"` sensor modes on the fly (to be exposed via a future web UI).

## Installation

A provided `install.sh` script automates the installation and setup on a clean Debian system.

### Prerequisites

- Debian (or a Debian-based distribution)
- PostgreSQL server
- Python 3

### Run the Installer

1. Place all project files (`app.py`, `mqtt_handler.py`, `relay_control.py`, `database_setup.py`, and `install.sh`) in a single directory.
2. Make the install script executable:
   ```bash
   chmod +x install.sh
