#!/bin/bash

: ${DATABASE_URL:?"Error: DATABASE_URL environment variable not set"}
REPOSITORY_NAME=${REPOSITORY_NAME:-logstash_snapshots}
if [ -z "$1" ]; then
  echo "Usage: restore-index.sh INDEXNAME"
  exit
fi

# We need to be a able to allow self-signed certs for testing purposes
CURL_OPTS=${CURL_OPTS:-}

# Normalize DATABASE_URL by removing the trailing slash.
DATABASE_URL="${DATABASE_URL%/}"

REPOSITORY_URL=${DATABASE_URL}/_snapshot/${REPOSITORY_NAME}
curl "$CURL_OPTS" -w "\n" -XPOST ${REPOSITORY_URL}/$1/_restore
