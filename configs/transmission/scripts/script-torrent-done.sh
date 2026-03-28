#!/usr/bin/env bash
set -euo pipefail

TELEGRAM_ADMIN_ID_FILE="${TELEGRAM_ADMIN_ID_FILE:-/etc/secrets/telegram_admin_id}"
TELEGRAM_API_TOKEN_FILE="${TELEGRAM_API_TOKEN_FILE:-/etc/secrets/telegram_api_token}"

# Check if secret files exist
if [[ ! -f "${TELEGRAM_ADMIN_ID_FILE}" || ! -f "${TELEGRAM_API_TOKEN_FILE}" ]]; then
  echo "Error: Secret files are missing - exiting without sending the notification" >&2
  exit 1
fi

# Read secrets
TELEGRAM_ADMIN_ID="$(cat "${TELEGRAM_ADMIN_ID_FILE}")"
TELEGRAM_API_TOKEN="$(cat "${TELEGRAM_API_TOKEN_FILE}")"

if [[ -z "${TELEGRAM_ADMIN_ID}" || -z "${TELEGRAM_API_TOKEN}" ]]; then
  echo "Error: Telegram variables are missing - exiting without sending the notification" >&2
  exit 1
fi


if [[ -z "${TR_TORRENT_NAME:-}" || -z "${TR_TIME_LOCALTIME:-}" ]]; then
  echo "Error: Transmission variables are missing - exiting without sending the notification" >&2
  exit 1
fi

TORRENT_TIME="$(date -d "${TR_TIME_LOCALTIME}" +"%-d %b, %-H:%M")"

escape_html() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&#39;}"
  printf '%s' "$s"
}

# Escape the torrent name
TORRENT_NAME_ESC="$(escape_html "${TR_TORRENT_NAME}")"

# Send the notification
if ! curl --silent --show-error --fail \
  --retry 3 \
  --max-time 30 \
  --output /dev/null \
  --data-urlencode "chat_id=${TELEGRAM_ADMIN_ID}" \
  --data-urlencode "text=The torrent <b>${TORRENT_NAME_ESC}</b> was downloaded on ${TORRENT_TIME}." \
  --data-urlencode "parse_mode=HTML" \
  "https://api.telegram.org/bot${TELEGRAM_API_TOKEN}/sendMessage"; then
  echo "Error: Could not send the notification" >&2
  exit 1
fi