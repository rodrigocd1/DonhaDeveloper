#!/usr/bin/env bash

set -u

check() {
  printf '%s=%s\n' "$1" "$2"
}

work="${1:-W-018973}"

if command -v sf >/dev/null 2>&1; then
  check "SF_CLI" "FOUND"
else
  check "SF_CLI" "MISSING"
fi

if command -v node >/dev/null 2>&1; then
  check "NODE" "FOUND"
else
  check "NODE" "MISSING"
fi

missing_env=0
for name in SF_ELERA_USERNAME SF_ELERA_CLIENT_ID SF_ELERA_JWT_KEY_FILE SF_ELERA_INSTANCE_URL; do
  value="${!name-}"
  if [ -z "$value" ]; then
    missing_env=1
  fi
done

if [ "$missing_env" -eq 0 ]; then
  check "ENV_VARS" "FOUND"
else
  check "ENV_VARS" "MISSING"
fi

if [ -n "${SF_ELERA_JWT_KEY_FILE-}" ] && [ -f "$SF_ELERA_JWT_KEY_FILE" ]; then
  check "JWT_KEY_FILE" "FOUND"
else
  check "JWT_KEY_FILE" "MISSING"
fi

if command -v sf >/dev/null 2>&1 && sf org display --target-org elera-work-check --json >/dev/null 2>&1; then
  check "ALIAS" "FOUND"
else
  check "ALIAS" "AUTH_ERROR"
fi

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
check_script="$script_dir/check-work.sh"

if [ -f "$check_script" ]; then
  check "CHECK_WORK_SCRIPT" "FOUND"
else
  check "CHECK_WORK_SCRIPT" "MISSING"
  exit 0
fi

work_result="$("$check_script" "$work" 2>/dev/null || true)"
case "$work_result" in
  FOUND|NOT_FOUND|INVALID_WORK|AUTH_ERROR)
    check "WORK_RESULT" "$work_result"
    ;;
  *)
    check "WORK_RESULT" "UNKNOWN"
    ;;
esac
