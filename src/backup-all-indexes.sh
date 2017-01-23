#!/bin/bash

NOW=$(date +"%m-%d-%Y %H-%M")

echo "$NOW: backup-all-indexes.sh - Verifying required environment variables"

: ${DATABASE_URL:?"Error: DATABASE_URL environment variable not set"}
: ${S3_BUCKET:?"Error: S3_BUCKET environment variable not set"}
: ${S3_ACCESS_KEY_ID:?"Error: S3_ACCESS_KEY_ID environment variable not set"}
: ${S3_SECRET_ACCESS_KEY:?"Error: S3_SECRET_ACCESS_KEY environment variable not set"}

# Normalize DATABASE_URL by removing the trailing slash.
DATABASE_URL="${DATABASE_URL%/}"

S3_REGION=${S3_REGION:-us-east-1}
REPOSITORY_NAME=${REPOSITORY_NAME:-logstash_snapshots}
WAIT_SECONDS=${WAIT_SECONDS:-1800}
MAX_DAYS_TO_KEEP=${MAX_DAYS_TO_KEEP:-30}
REPOSITORY_URL=${DATABASE_URL}/_snapshot/${REPOSITORY_NAME}

ES_VERSION=$(curl -sS $DATABASE_URL?format=yaml | grep number | cut -d'"' -f2)
ES_VERSION_COMPARED_TO_50=$(apk version -t "$ES_VERSION" "4.9")

if [ $ES_VERSION_COMPARED_TO_50 = '<' ]; then
    REPOSITORY_PLUGIN=cloud-aws
else
    REPOSITORY_PLUGIN=repository-s3
fi

backup_index ()
{
  : ${1:?"Error: expected index name passed as parameter"}
  local INDEX_NAME=$1
  local SNAPSHOT_URL=${REPOSITORY_URL}/${INDEX_NAME}
  local INDEX_URL=${DATABASE_URL}/${INDEX_NAME}

  grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL})
  if [ $? -ne 0 ]; then
    echo "$NOW: Scheduling snapshot."
    # If the snapshot exists but isn't in a success state, delete it so that we can try again.
    grep -qE "FAILED|PARTIAL|IN_PROGRESS" <(curl -sS ${SNAPSHOT_URL}) && curl -sS -XDELETE ${SNAPSHOT_URL}
    # Indexes have to be open for snapshots to work.
    curl -sS -XPOST "${INDEX_URL}/_open"

    curl --fail -w "\n" -sS -XPUT ${SNAPSHOT_URL} -d "{
      \"indices\": \"${INDEX_NAME}\",
      \"include_global_state\": false
    }" || return 1

    echo "$NOW: Waiting for snapshot to finish..."
    timeout "${WAIT_SECONDS}" bash -c "until grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL}); do sleep 1; done" || return 1
  fi

  echo "Deleting ${INDEX_NAME} from Elasticsearch."
  curl -w "\n" -sS -XDELETE ${INDEX_URL}
}

# Ensure that Elasticsearch has the cloud-aws plugin.
grep -q $REPOSITORY_PLUGIN <(curl -sS ${DATABASE_URL}/_cat/plugins)
if [ $? -ne 0 ]; then
  echo "$NOW: Elasticsearch server does not have cloud-aws plugin installed. Exiting."
  exit 1
fi

echo "$NOW: Ensuring Elasticsearch snapshot repository ${REPOSITORY_NAME} exists..."
curl -w "\n" -sS -XPUT ${REPOSITORY_URL} -d "{
  \"type\": \"s3\",
  \"settings\": {
    \"bucket\" : \"${S3_BUCKET}\",
    \"base_path\": \"${S3_BUCKET_BASE_PATH}\",
    \"access_key\": \"${S3_ACCESS_KEY_ID}\",
    \"secret_key\": \"${S3_SECRET_ACCESS_KEY}\",
    \"region\": \"${S3_REGION}\",
    \"protocol\": \"https\",
    \"server_side_encryption\": true
  }
}"

CUTOFF_DATE=$(date --date="${MAX_DAYS_TO_KEEP} days ago" +"%Y.%m.%d")
echo "Archiving all indexes with logs before ${CUTOFF_DATE}."
SUBSTITUTION='s/.*\(logstash-[0-9\.]\{10\}\).*/\1/'
for index_name in $(curl -sS ${DATABASE_URL}/_cat/indices | grep logstash- | sed $SUBSTITUTION | sort); do
  if [[ "${index_name:9}" < "${CUTOFF_DATE}" ]]; then
      echo "$NOW: Ensuring ${index_name} is archived..."
      backup_index ${index_name}
      if [ $? -eq 0 ]; then
          echo "$NOW: ${index_name} archived."
      else
          echo "$NOW: ${index_name} archival failed."
      fi
  fi
done
echo "$NOW: Finished archiving."
