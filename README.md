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
Run the installer (with sudo if needed):
bash
Copy
sudo ./install.sh
The script will:
Create necessary directories under /opt/beerpi and /var/log/beerpi
Install required system packages (Python, PostgreSQL, etc.)
Set up a Python virtual environment and install dependencies
Copy project files into /opt/beerpi/backend
Create a sample configuration file in /opt/beerpi/config/config.yaml
Set up a systemd service (beerpi-backend.service) to manage the backend
Configuration
The configuration file is located at /opt/beerpi/config/config.yaml. An example configuration:

yaml
Copy
database:
  host: "localhost"
  database: "beerpi"
  user: "beerpi_user"
  password: "beerpi_pass"
  port: 5432

mqtt:
  broker: "localhost"
  port: 1883
  username: "mqtt_user"
  password: "mqtt_pass"
  temperature_topic: "beerpi/data/temperature"
  relay_topic: "beerpi/data/relay"
  command_topic: "beerpi/commands"
  discovery_prefix: "homeassistant"

logging:
  log_dir: "/var/log/beerpi"
  backend_log: "backend.log"
  error_log: "error.log"
  max_bytes: 1048576
  backup_count: 5

version: "2.0.0"

relay_control:
  upper_threshold: 25.0
  lower_threshold: 18.0
REST API Endpoints
GET /test-db:
Tests the connection to the PostgreSQL database.

GET /version:
Returns the current application version.

GET /relay/state:
Returns the current relay state (e.g., {"state": "OFF", "mode": "auto"}).

GET /temperature/logs:
Returns up to the last 100 temperature log entries.

GET /settings:
Returns current system settings, including relay control thresholds and sensor mode.

PUT /settings:
Updates system settings. Example payload:

json
Copy
{
    "relay_control": {"upper_threshold": 27.0, "lower_threshold": 20.0},
    "sensor": {"mode": "simulated"}
}
This allows dynamic updates without restarting BeerPi.

MQTT Discovery
BeerPi publishes MQTT discovery messages to integrate with Home Assistant. The discovery topics (by default) are:

homeassistant/sensor/beerpi_temperature/config
homeassistant/switch/beerpi_relay/config
These discovery messages configure the entities in Home Assistant (including their unique IDs, state topics, command topics, and payloads).

Sensor Modes
BeerPi supports two sensor modes:

Simulated Mode:
Generates dynamic temperature values using a sine wave (useful for testing).
Real Mode:
Attempts to read from a DS18B20 sensor. If no sensor is available, it falls back to a default value.
The sensor mode is managed via the global sensor_config dictionary and can be updated on the fly using the /settings endpoint.

WebSocket Integration
The backend uses Flask-SocketIO (with eventlet) to broadcast real-time updates. Clients can connect to receive:

Temperature updates (temperature_update event)
Relay state updates (relay_state_update event)
Testing
Unit and integration tests have been developed using Pytest. The test files reside in the tests directory.

Running the Tests
Install Pytest in your virtual environment:
bash
Copy
pip install pytest
Run the tests from your backend directory:
bash
Copy
pytest
Troubleshooting
Logs:
Check /var/log/beerpi/backend.log and /var/log/beerpi/error.log for detailed runtime messages.
MQTT:
Use an MQTT client (e.g., MQTT Explorer) to verify discovery messages and sensor data topics.
Database:
Ensure PostgreSQL is running and the credentials in config.yaml are correct.
WebSocket:
Use a browser-based client or a Node.js test script to verify real-time events.
Future Enhancements
Real Sensor Integration:
Integrate a DS18B20 sensor for actual temperature readings.
Enhanced Diagnostic Endpoints:
Add endpoints for system status and diagnostics.
Front-End UI:
Develop a web-based user interface for monitoring and control.
Automated Testing:
Expand the test suite to cover MQTT and WebSocket interactions more thoroughly.
License
(Include your license information here, if applicable)
