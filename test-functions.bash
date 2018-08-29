#!/bin/bash
function wait_for_request {
  CONTAINER=$1
  shift

  for _ in $(seq 1 30); do
    if docker exec -it "$CONTAINER" curl -f -v "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "No response"
  docker logs "$CONTAINER"
  return 1
}

function create_index {
  CONTAINER=$1
  docker exec -it "$CONTAINER" curl -X PUT "localhost:9200/logstash-$2" -H 'Content-Type: application/json' > /dev/null
}

function create_indices {
	CONTAINER="$1"
  DAY=$2
	while [ $DAY -gt 0 ]; do
    DAY=$[$DAY-1]
	  create_index "$CONTAINER" "$(date --date="${DAY} days ago" +"%Y.%m.%d")"
	done
	echo "$2 daily logstach indices created."
}

function verify_index {
  if  docker exec -it "$CONTAINER" curl "localhost:9200/_cat/indices" | grep "$1" > /dev/null; then
    echo "present"
  else
  	echo "missing"
  fi
}

function check_retention_days {
	CONTAINER="$1"
	 docker exec -it "$CONTAINER" curl "localhost:9200/_cat/indices" | wc -l
}

function s3_count {
	INDEXES="$1"
	s3cmd --access_key="$S3_ACCESS_KEY_ID" --secret_key="$S3_SECRET_ACCESS_KEY" ls "s3://$INDEXES" | wc -l
}

function cleanup {
  echo "Cleaning up"
  docker rm -f "$DB_CONTAINER" "$DATA_CONTAINER" >/dev/null 2>&1 || true
  #docker rmi "$IMG" || true

  docker rm -f test-backup > /dev/null 2>&1 || true
  #docker rmi aptible/s3-backup || true

  #s3cmd delete S3_PATH
  s3cmd --access_key="$S3_ACCESS_KEY_ID" --secret_key="$S3_SECRET_ACCESS_KEY" rm -r "s3://$S3_BUCKET/$S3_PATH/" > /dev/null || true
}
