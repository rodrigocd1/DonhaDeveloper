#!/usr/bin/env bash

set -u

status() {
  printf '%s\n' "$1"
  exit 0
}

for name in SF_ELERA_USERNAME SF_ELERA_CLIENT_ID SF_ELERA_JWT_KEY_FILE SF_ELERA_INSTANCE_URL; do
  value="${!name-}"
  if [ -z "$value" ]; then
    status "AUTH_ERROR"
  fi
done

if [ ! -f "$SF_ELERA_JWT_KEY_FILE" ]; then
  status "AUTH_ERROR"
fi

if sf org login jwt \
  --username "$SF_ELERA_USERNAME" \
  --client-id "$SF_ELERA_CLIENT_ID" \
  --jwt-key-file "$SF_ELERA_JWT_KEY_FILE" \
  --instance-url "$SF_ELERA_INSTANCE_URL" \
  --alias elera-work-check \
  --json >/dev/null 2>&1; then
  status "AUTH_OK"
fi

status "AUTH_ERROR"
