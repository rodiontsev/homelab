#!/bin/bash

# Verify HTTP redirect
# Usage: ./check_redirect.sh <source_url> <expected_destination>

SOURCE_URL="${1:-http://example.com/}"
EXPECTED_URL="${2:-https://www.example.com/}"

# Get final URL after following redirects
FINAL_URL=$(curl -I -L -s -w '%{url_effective}' -o /dev/null "$SOURCE_URL")
EXIT_CODE=$?
 
# Check if curl succeeded
if [ $EXIT_CODE -ne 0 ]; then
    echo "ERROR: Could not connect to $SOURCE_URL" >&2
    exit $EXIT_CODE
fi
 
# Normalise URLs - remove trailing slash for comparison if needed
FINAL_URL_FMT="${FINAL_URL%/}"
EXPECTED_URL_FMT="${EXPECTED_URL%/}"
 
# Compare URLs
if [ "$FINAL_URL_FMT" = "$EXPECTED_URL_FMT" ]; then
    exit 0
fi

# Show what we got vs what we expected
echo "ERROR: Redirect mismatch" >&2
echo "  Expected: $EXPECTED_URL_FMT" >&2
echo "  Actual:   $FINAL_URL_FMT" >&2

exit 1