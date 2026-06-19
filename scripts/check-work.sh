#!/usr/bin/env bash

set -u

status() {
  printf '%s\n' "$1"
  exit 0
}

if ! command -v sf >/dev/null 2>&1; then
  status "AUTH_ERROR"
fi

if ! command -v node >/dev/null 2>&1; then
  status "AUTH_ERROR"
fi

work_input="${1-}"
normalized_work="$(
  WORK_INPUT="$work_input" node 2>/dev/null <<'NODE'
const input = (process.env.WORK_INPUT || '').trim().replace(/\\/g, '/');
const withoutFolder = input.replace(/^works\//i, '').replace(/^\/+|\/+$/g, '');
const markdownLink = withoutFolder.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
const candidate = markdownLink ? markdownLink[1].trim() : withoutFolder;
const match = candidate.match(/^([Ww])[-\s]*(\d{1,6})$/);

function invalid() {
  process.stdout.write('INVALID_WORK');
  process.exit(0);
}

if (!match) {
  invalid();
}

const number = String(Number.parseInt(match[2], 10)).padStart(6, '0');
process.stdout.write(`W-${number}`);
NODE
)"

if [ "$normalized_work" = "INVALID_WORK" ] || [ -z "$normalized_work" ]; then
  status "INVALID_WORK"
fi

if ! sf org display --target-org elera-work-check --json >/dev/null 2>&1; then
  status "AUTH_ERROR"
fi

escaped_work="$(
  NORMALIZED_WORK="$normalized_work" node 2>/dev/null <<'NODE'
process.stdout.write((process.env.NORMALIZED_WORK || '').replace(/'/g, "''"));
NODE
)"

query="SELECT Id FROM agf__ADM_Work__c WHERE Name = '$escaped_work' LIMIT 1"
query_output="$(sf data query --target-org elera-work-check --query "$query" --json 2>/dev/null)" || status "AUTH_ERROR"

total_size="$(
  QUERY_OUTPUT="$query_output" node 2>/dev/null <<'NODE'
try {
  const payload = JSON.parse(process.env.QUERY_OUTPUT || '{}');
  const total = payload && payload.result && Number.isInteger(payload.result.totalSize)
    ? payload.result.totalSize
    : -1;
  process.stdout.write(String(total));
} catch {
  process.stdout.write('-1');
}
NODE
)"

if [ "$total_size" -lt 0 ] 2>/dev/null; then
  status "AUTH_ERROR"
fi

if [ "$total_size" -gt 0 ]; then
  status "FOUND"
fi

status "NOT_FOUND"
