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

  grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL})
  if [ $? -ne 0 ]; then
    echo "Scheduling snapshot."
    curl --fail -w "\n" -sS -XPUT ${SNAPSHOT_URL} -d "{
      \"indices\": \"${INDEX_NAME}\",
      \"include_global_state\": false
    }" || return 1

    echo "Waiting for snapshot to finish..."
    timeout "${WAIT_SECONDS}" bash -c "until grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL}); do sleep 1; done" || return 1
  fi

  echo "Deleting ${INDEX_NAME} from Elasticsearch."
  curl -w "\n" -sS -XDELETE ${INDEX_URL}
}

# Ensure that Elasticsearch has the cloud-aws plugin.
grep -q cloud-aws <(curl -sS ${DATABASE_URL}/_cat/plugins)
if [ $? -ne 0 ]; then
  echo "Elasticsearch server does not have cloud-aws plugin installed. Exiting."
  exit 1
fi

echo "Ensuring Elasticsearch snapshot repository ${REPOSITORY_NAME} exists..."
curl -w "\n" -sS -XPUT ${REPOSITORY_URL} -d "{
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

CUTOFF_DATE=$(date --date="${MAX_DAYS_TO_KEEP} days ago" +"%Y.%m.%d")
echo "Archiving all indexes with logs before ${CUTOFF_DATE}."
SUBSTITUTION='s/.*\(logstash-[0-9\.]\{10\}\).*/\1/'
for index_name in $(curl -sS ${DATABASE_URL}/_cat/indices | grep logstash- | sed $SUBSTITUTION); do
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
echo "Finished archiving."