#!/bin/sh

aptible config:set --app es5-logs-s3-backup  DATABASE_URL=`credstash get prod.es5_s3_backups.ES5_DB_URL` S3_BUCKET=virta-es5-prod-logs S3_ACCESS_KEY_ID=`credstash get prod.es5_s3_backups.AWS_ACCESS_KEY` S3_SECRET_ACCESS_KEY=`credstash get prod.es5_s3_backups.AWS_SECRET_KEY` MAX_DAYS_TO_KEEP=14

