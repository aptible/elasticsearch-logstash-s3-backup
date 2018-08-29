#!/bin/bash
set -o errexit
set -o nounset

IMG="$1"

DB_CONTAINER="elastic"
DATA_CONTAINER="${DB_CONTAINER}-data"

S3_BUCKET="${S3_BUCKET:-aptible-unit-tests}"
S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
S3_REGION="${S3_REGION:-us-east-1}"
S3_PATH="$(date)"

source ./test-functions.bash

trap cleanup EXIT
cleanup


# Ensure s3cmd is present
if ! which s3cmd; then
  sudo apt-get -y install s3cmd
fi


docker build --tag aptible/s3-backup . > /dev/null
# FIX THE CURL CERT ISSUE


echo "Set up Elasticsearch"
docker create --name "$DATA_CONTAINER" "$IMG"

echo "Initializing DB"
docker run -it --rm \
  -e USERNAME=user -e PASSPHRASE=pass -e DATABASE=db \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG" --initialize \
  >/dev/null 2>&1

echo "Starting DB"
docker run -d --name="$DB_CONTAINER" \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG"

echo "Waiting for DB to come online"
wait_for_request "$DB_CONTAINER" "http://localhost:9200"
echo "Ready"

ES_IP="$(docker inspect --format='{{.NetworkSettings.Networks.bridge.IPAddress}}' ${DB_CONTAINER})"
ES_URL="https://user:pass@${ES_IP}"



echo "Creating test indexes"
create_indices "$DB_CONTAINER" 40

echo "Ensuring there are 40 indexes in Elasticsearch"
[ "$(check_retention_days "$DB_CONTAINER")" == "40" ]

echo "Archiving to keep only 30 days of indexes"
# Archive the default amount of days (30)
docker run --rm \
  --entrypoint "/opt/app/src/backup-all-indexes.sh" \
  -e CURL_OPTS="-k" \
  -e DATABASE_URL="$ES_URL" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  -e S3_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
  -e S3_BUCKET_BASE_PATH="$S3_PATH" \
  --name "test-backup" \
  "aptible/s3-backup" > /dev/null
echo "The archive completed"

echo "Checking that today and the previous 30 indexes are retained in Elasticsearch"
[ "$(check_retention_days "$DB_CONTAINER")" == "31" ]

echo "Checking that the older 9 got backed up to S3"
[ "$(s3_count "$S3_BUCKET/$S3_PATH/indices/")" == "9" ]


echo "Testing again, with MAX_DAYS_TO_KEEP=20"
docker run --rm \
  --entrypoint "/opt/app/src/backup-all-indexes.sh" \
  -e CURL_OPTS="-k" \
  -e DATABASE_URL="$ES_URL" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  -e S3_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
  -e S3_BUCKET_BASE_PATH="$S3_PATH" \
  -e MAX_DAYS_TO_KEEP="20" \
  --name "test-backup" \
  "aptible/s3-backup" > /dev/null

[ "$(check_retention_days "$DB_CONTAINER")" == "21" ]

[ "$(s3_count "$S3_BUCKET/$S3_PATH/indices/")" == "19" ]


echo "Testing restoring a an index from s3"

DELETED_INDEX="logstash-$(date --date="25 days ago" +"%Y.%m.%d")"

[ "$(verify_index "$DELETED_INDEX")" == "missing" ]

docker run -it --rm \
  --entrypoint "/opt/app/src/restore-index.sh" \
  -e CURL_OPTS="-k" \
  -e DATABASE_URL="$ES_URL" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  -e S3_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
  -e S3_BUCKET_BASE_PATH="$S3_PATH" \
  --name "test-backup" \
  "aptible/s3-backup" "$DELETED_INDEX" > /dev/null

[ "$(verify_index "$DELETED_INDEX")" == "present" ]

echo "All tests passed!"
