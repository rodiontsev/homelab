#!/bin/bash
 
# Check if port is open (listening)
# Usage: ./check_port.sh example.com 80
 
HOST="${1:-example.com}"
PORT="${2:-80}"

if [[ -z "$HOST" ]] || [[ -z "$PORT" ]]; then
    echo "Usage: $0 <host> <port>" >&2
    exit 2
fi

# Try netcat first
if command -v nc &> /dev/null; then
    if nc -z -w3 "$HOST" "$PORT" 2>/dev/null; then
        exit 0
    fi
fi

# Fallback to /dev/tcp
if timeout 3 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
    exit 0
fi

exit 1