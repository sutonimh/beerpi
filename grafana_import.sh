#!/bin/bash
# grafana_import.sh - Version 1.2
# This script configures the InfluxDB datasource and imports the BeerPi Temperature dashboard into Grafana.
# It accepts the Grafana admin username and password as command-line arguments.
# If no arguments are provided, it falls back to the environment variables GRAFANA_USER and GRAFANA_PASS.
#
# WARNING: This script will overwrite any existing datasource named "InfluxDB" and any dashboard with UID "temperature_dashboard".
#
set -e

# Use command-line arguments if provided; otherwise, use environment variables.
if [ -n "$1" ] && [ -n "$2" ]; then
    GRAFANA_USER="$1"
    GRAFANA_PASS="$2"
fi

if [ -z "$GRAFANA_USER" ] || [ -z "$GRAFANA_PASS" ]; then
    echo "ERROR: Grafana credentials not provided via arguments or environment variables."
    exit 1
fi

print_sep() {
    echo "----------------------------------------"
}

print_sep
echo "Starting Grafana datasource and dashboard import script (grafana_import.sh - Version 1.2)."
print_sep

########################################
# Configure InfluxDB datasource.
########################################
echo "Configuring Grafana InfluxDB datasource..."
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
echo "Sending datasource configuration to Grafana API..."
DS_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "${DS_PAYLOAD}" http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/datasources)
echo "Datasource API response: ${DS_RESPONSE}"
if echo "$DS_RESPONSE" | grep -q '"message":"Datasource added"'; then
    echo "Datasource configured successfully."
else
    echo "WARNING: Datasource configuration may have failed. Please check the response above."
fi
print_sep

########################################
# Import BeerPi Temperature dashboard.
########################################
echo "Importing BeerPi Temperature dashboard into Grafana..."
DASHBOARD_JSON=$(cat <<'EOF'
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
echo "Sending dashboard JSON to Grafana API..."
DB_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "${DASHBOARD_JSON}" http://${GRAFANA_USER}:${GRAFANA_PASS}@localhost:3000/api/dashboards/db)
echo "Dashboard API response: ${DB_RESPONSE}"
if echo "$DB_RESPONSE" | grep -q '"status":"success"'; then
    echo "Dashboard imported successfully."
else
    echo "WARNING: Dashboard import may have failed. Please check the response above."
fi
print_sep

echo "Grafana datasource and dashboard import complete."
exit 0
