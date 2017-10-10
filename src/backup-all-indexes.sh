#!/bin/bash

function now() {
  date +"%m-%d-%Y %H-%M"
}

echo "$(now): backup-all-indexes.sh - Verifying required environment variables"

: ${DATABASE_URL:?"Error: DATABASE_URL environment variable not set"}
: ${S3_BUCKET:?"Error: S3_BUCKET environment variable not set"}
: ${S3_ACCESS_KEY_ID:?"Error: S3_ACCESS_KEY_ID environment variable not set"}
: ${S3_SECRET_ACCESS_KEY:?"Error: S3_SECRET_ACCESS_KEY environment variable not set"}
# list of index patterns to backup, should be separated with white space 'logstash filebeat'
INDEX_ARRAY=${INDEX_ARRAY:-logstash}


# Normalize DATABASE_URL by removing the trailing slash.
DATABASE_URL="${DATABASE_URL%/}"

# Set some defaults
S3_REGION=${S3_REGION:-us-east-1}
REPOSITORY_NAME=${REPOSITORY_NAME:-logstash_snapshots}
WAIT_SECONDS=${WAIT_SECONDS:-1800}
MAX_DAYS_TO_KEEP=${MAX_DAYS_TO_KEEP:-60}
REPOSITORY_URL=${DATABASE_URL}/_snapshot/${REPOSITORY_NAME}
SLACK_HOOK=${SLACK_HOOK}
SLACK_CHANNEL=${SLACK_CHANNEL:-backups}
SLACK_USER=${SLACK_USER:-backup-bot}
SLACK_EMO=${SLACK_EMO:-:soon:}


#COLORS
R="\e[31m"
G="\e[32m"
N="\e[39m"
B="\e[5m"
NB="\e[25m"


# Ensure that we don't delete indices that are being logged. Using 1 should
# actually be fine here as long as everyone's on the same timezone, but let's
# be safe and require at least 2 days.
if [[ "$MAX_DAYS_TO_KEEP" -lt 2 ]]; then
  echo "$(now): MAX_DAYS_TO_KEEP must be an integer >= 2."
  echo "$(now): Using lower values may break archiving."
  exit 1
fi

ES_VERSION=$(curl -sS $DATABASE_URL?format=yaml | grep number | cut -d'"' -f2)
ES_VERSION_COMPARED_TO_50=$(apk version -t "$ES_VERSION" "4.9")

if [ $ES_VERSION_COMPARED_TO_50 = '<' ]; then
    REPOSITORY_PLUGIN=cloud-aws
else
    REPOSITORY_PLUGIN=repository-s3
fi


# small slack notification function

slack_send() { 

  curl -XPOST --data-urlencode 'payload={"channel": "'"$SLACK_CHANNEL"'", "text": "'"$1"'", "username": "'"$SLACK_USER"'", "icon_emoji": "'"$2"'" }' $SLACK_HOOK

}


archive_index ()
{
  : ${1:?"Error: expected index name passed as parameter"}
  local INDEX_NAME=$1
  local SNAPSHOT_URL=${REPOSITORY_URL}/${INDEX_NAME}
  local INDEX_URL=${DATABASE_URL}/${INDEX_NAME}

  grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL})
  if [ $? -ne 0 ]; then
    echo "$(now): Scheduling snapshot."
    # If the snapshot exists but isn't in a success state, delete it so that we can try again.
    grep -qE "FAILED|PARTIAL|IN_PROGRESS" <(curl -sS ${SNAPSHOT_URL}) && curl -sS -XDELETE ${SNAPSHOT_URL}

    # Indexes have to be open for snapshots to work.
    curl -sS -XPOST "${INDEX_URL}/_open"

    curl --fail -w "\n" -sS -XPUT ${SNAPSHOT_URL} -d "{
      \"indices\": \"${INDEX_NAME}\",
      \"ignore_unavailable\": true,
      \"include_global_state\": false
    }" || return 1

    echo "$(now): Waiting for snapshot to finish..."
    timeout "${WAIT_SECONDS}" bash -c "until grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL}); do sleep 1; done" || return 1
  fi

  echo "Deleting ${INDEX_NAME} from Elasticsearch."
  curl -w "\n" -sS -XDELETE ${INDEX_URL}
}

backup_index ()
{
  : ${1:?"Error: expected index name passed as parameter"}
  local INDEX_NAME=$1
  local SNAPSHOT_URL=${REPOSITORY_URL}/${INDEX_NAME}
  local INDEX_URL=${DATABASE_URL}/${INDEX_NAME}

  grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL})

  if [ $? -ne 0 ]; then
    echo "$(now): Scheduling snapshot."
    # If the snapshot exists but isn't in a success state, delete it so that we can try again.
    grep -qE "FAILED|PARTIAL|IN_PROGRESS" <(curl -sS ${SNAPSHOT_URL}) && curl -sS -XDELETE ${SNAPSHOT_URL}
    # Indexes have to be open for snapshots to work.
    curl -sS -XPOST "${INDEX_URL}/_open"

    curl --fail -w "\n" -sS -XPUT ${SNAPSHOT_URL} -d "{
      \"indices\": \"${INDEX_NAME}\",
      \"include_global_state\": false
    }" || return 1

    echo "$(now): Waiting for snapshot to finish..."
    timeout "${WAIT_SECONDS}" bash -c "until grep -q SUCCESS <(curl -sS ${SNAPSHOT_URL}); do sleep 1; done" || return 1
    #increase backup counter
    let bk++
  fi


         echo "$(now): Ensuring ${index_name} is backuped..."
 




}

# Ensure that Elasticsearch has the cloud-aws plugin.
grep -q $REPOSITORY_PLUGIN <(curl -sS ${DATABASE_URL}/_cat/plugins)
if [ $? -ne 0 ]; then
  echo "$(now): Elasticsearch server does not have the ${REPOSITORY_PLUGIN} plugin installed. Exiting."
  exit 1
fi

echo "$(now): Ensuring Elasticsearch snapshot repository ${REPOSITORY_NAME} exists..."
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

#define array to store results
arr=()
CUTOFF_DATE=$(date --date="${MAX_DAYS_TO_KEEP} days ago" +"%Y.%m.%d")

echo "$(now) Archiving all indexes with logs before ${CUTOFF_DATE}."

# itterate array of indices
for index_nm in ${INDEX_ARRAY[@]}; do

  #set counters for ar - archived index, bk - backuped and fl - failed
  ar=0
  bk=0
  fl=0


    # regexp to catch index with date from string
    SUBSTITUTION="s/.*\($index_nm-[0-9\.]\{10\}\).*/\1/"
    SUBSTITUTION_date="s/.*([0-9]{4}\.[0-9]{2}\.[0-9]{2}).*/\1/"
       # intterate index strings
       for index in $(curl -sS ${DATABASE_URL}/_cat/indices | grep $index_nm- | sed $SUBSTITUTION | sort); do

          # debug information
          echo "$index"
          CURR_DATE=`echo $index | sed -re $SUBSTITUTION_date`
          # if date less then cutoff date, archive index to s3 and delete from elasticsearch
          if [[ "$CURR_DATE" < "${CUTOFF_DATE}" ]]; then

 
            echo "$(now): Ensuring ${index} is archived..."

            archive_index ${index}
 
            if [ $? -eq 0 ]; then
              echo "$(now): ${index} archived."
              let ar++
            else
              echo "$(now): ${index} archival failed."
               let fl++ 
           fi
         # if less then cuttoff date, just backup it to s3 without deletion
         else 
            echo "$(now): backup of ${index} started..."
            backup_index ${index}
            if [ $? -eq 0 ]; then
              echo "$(now): ${index} backuped."
            else
              echo "$(now): ${index} backup failed."
              let fl++ 
            fi

         fi
       done
   
    echo -e "results of archiving are -> index_name -> $B $index_nm $NB backuped -> $G  $bk $N, archived -> $ar $R, failed -> $fl $N"
# formating array with message, that ll be send to slack

    arr+=("results of archiving index_name -> *$index_nm*  are: \n  backuped ->   *$bk* , archived -> *$ar*, failed *$fl*\n")

done
echo "$(now): Finished archiving."


# if slack webhook set, send notify
if [[ -z "$SLACK_HOOK" ]]; then

  echo "slack hook is not defined"
else

   slack_send "${arr[*]}" "$SLACK_EMO"

fi
