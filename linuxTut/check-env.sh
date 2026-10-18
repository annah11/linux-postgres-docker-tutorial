#!/bin/bash

ENV_FILE="$(dirname "$0")/.env"

# 1. Make sure the config file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Copy .env.example to .env first."
  exit 1
fi

# 2. Load variables
source "$ENV_FILE"
echo "Environment: $APP_ENV"

# 3. Is the database listening?
if ! ss -ltn | grep -q ":$DB_PORT "; then
  echo "Error: Postgres is not running on port $DB_PORT"
  exit 1
fi

# 4. Is the app port free?
if ss -ltn | grep -q ":$APP_PORT "; then
  echo "Error: port $APP_PORT is already in use"
  exit 1
fi

echo "All checks passed."
