#!/bin/bash
# grafana_import.sh - Version 1.2
# This script configures the InfluxDB datasource and imports the BeerPi Temperature dashboard into Grafana.
# It expects that Grafana is running and that /etc/grafana/grafana.ini is correctly configured.
#
# Usage: sudo ./grafana_import.sh
#
set -e

# (Optionally, you could set the credentials here or assume they are the same as used in grafana.sh.)
# For simplicity, we'll prompt here as well.
read -p "Enter Grafana admin username (default: admin): " GRAFANA_USER
GRAFANA_USER=${GRAFANA_USER:-admin}
read -sp "Enter Grafana admin password (default: admin): " GRAFANA_PASS
echo
GRAFANA_PASS=${GRAFANA_PASS:-admin}

echo "Using Grafana admin credentials: $GRAFANA_USER / $GRAFANA_PASS"

# Import the InfluxDB datasource.
DS_PAYLOAD=$(cat <<EOF
{
  "name": "InfluxDB",
  "type": "influxdb",
  "access": "proxy",
  "url": "http://localhost:8086",
  "database": "combined_sensor_db",
  "isDefault": true
}
EOF
)
echo "Importing InfluxDB datasource..."
DS_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "${DS_PAYLOAD}" \
  http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/datasources)
echo "Datasource API response: ${DS_RESPONSE}"

# Import the BeerPi Temperature dashboard.
DASHBOARD_JSON=$(cat <<EOF
{
  "dashboard": {
    "id": null,
    "uid": "temperature_dashboard",
    "title": "BeerPi Temperature",
    "folderId": 0,
    "tags": [ "temperature" ],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 1,
    "panels": [
      {
        "type": "graph",
        "title": "Temperature Over Time",
        "gridPos": { "x": 0, "y": 0, "w": 24, "h": 9 },
        "datasource": "InfluxDB",
        "targets": [
          {
            "measurement": "temperature",
            "groupBy": [
              { "type": "time", "params": [ "$__interval" ] }
            ],
            "select": [
              [
                { "type": "field", "params": [ "temperature" ] },
                { "type": "mean", "params": [] }
              ]
            ],
            "refId": "A"
          }
        ],
        "xaxis": { "mode": "time", "show": true },
        "yaxes": [
          { "format": "celsius", "label": "Temperature", "logBase": 1, "show": true },
          { "show": true }
        ]
      }
    ]
  },
  "overwrite": true
}
EOF
)
echo "Importing BeerPi Temperature dashboard..."
DB_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
  -d "${DASHBOARD_JSON}" \
  http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/dashboards/db)
echo "Dashboard API response: ${DB_RESPONSE}"

echo "Grafana datasource and dashboard import complete."
