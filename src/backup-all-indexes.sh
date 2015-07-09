#!/bin/bash

: ${DATABASE_URL:?"Error: DATABASE_URL environment variable not set"}
: ${S3_BUCKET:?"Error: S3_BUCKET environment variable not set"}
: ${S3_ACCESS_KEY_ID:?"Error: S3_ACCESS_KEY_ID environment variable not set"}
: ${S3_SECRET_ACCESS_KEY:?"Error: S3_SECRET_ACCESS_KEY environment variable not set"}
S3_REGION=${S3_REGION:-us-east-1}
REPOSITORY_NAME=${REPOSITORY_NAME:-logstash_snapshots}
WAIT_SECONDS=${WAIT_SECONDS:-1800}
MAX_DAYS_TO_KEEP=${MAX_DAYS_TO_KEEP:-30}
REPOSITORY_URL=${DATABASE_URL}/_snapshot/${REPOSITORY_NAME}

backup_index ()
{
  : ${1:?"Error: expected index name passed as parameter"}
  local INDEX_NAME=$1
  local SNAPSHOT_URL=${REPOSITORY_URL}/${INDEX_NAME}
  local INDEX_URL=${DATABASE_URL}/${INDEX_NAME}

  grep -q SUCCESS <(curl ${SNAPSHOT_URL} 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Scheduling snapshot."
    curl --fail -w "\n" -XPUT ${SNAPSHOT_URL} -d "{
      \"indices\": \"${INDEX_NAME}\",
      \"include_global_state\": false
    }" || return 1

    echo "Waiting for snapshot to finish..."
    timeout "${WAIT_SECONDS}" bash -c "until grep -q SUCCESS <(curl ${SNAPSHOT_URL} 2>/dev/null); do sleep 1; done" || return 1
  fi

  echo "Deleting ${INDEX_NAME} from Elasticsearch."
  curl -w "\n" -XDELETE ${INDEX_URL}
}

# Ensure that the snapshot repository exists.
REPO_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" ${REPOSITORY_URL})
if [ "$REPO_EXISTS" != 200 ]; then
  echo "Creating repository ${REPOSITORY_NAME} to store snapshots..."
  curl -w "\n" -XPUT ${REPOSITORY_URL} -d "{
    \"type\": \"s3\",
    \"settings\": {
      \"bucket\" : \"${S3_BUCKET}\",
      \"access_key\": \"${S3_ACCESS_KEY_ID}\",
      \"secret_key\": \"${S3_SECRET_ACCESS_KEY}\",
      \"region\": \"${S3_REGION}\",
      \"protocol\": \"https\",
      \"server_side_encryption\": true
    }
  }"
fi

CUTOFF_DATE=$(date --date="${MAX_DAYS_TO_KEEP} days ago" +"%Y.%m.%d")
echo "Archiving all indexes with logs before ${CUTOFF_DATE}."
for index_name in $(curl ${DATABASE_URL}/_cat/indices/logstash-* 2>/dev/null | cut -d' ' -f3); do
  if [[ "${index_name:9}" < "${CUTOFF_DATE}" ]]; then
      echo "Ensuring ${index_name} is archived..."
      backup_index ${index_name}
      if [ $? -eq 0 ]; then
          echo "${index_name} archived."
      else
          echo "${index_name} archival failed."
      fi
  fi
done
