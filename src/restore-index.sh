#!/bin/bash

: ${DATABASE_URL:?"Error: DATABASE_URL environment variable not set"}
REPOSITORY_NAME=${REPOSITORY_NAME:-logstash_snapshots}
if [ -z "$1" ]; then
  echo "Usage: restore-index.sh INDEXNAME"
  exit
fi

# Normalize DATABASE_URL by removing the trailing slash.
DATABASE_URL="${DATABASE_URL%/}"

REPOSITORY_URL=${DATABASE_URL}/_snapshot/${REPOSITORY_NAME}
curl -w "\n" -XPOST ${REPOSITORY_URL}/$1/_restore
