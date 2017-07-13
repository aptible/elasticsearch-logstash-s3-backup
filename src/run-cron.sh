#!/bin/bash
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 2 * * *"}
sed "s:CRON_SCHEDULE:${CRON_SCHEDULE}:g" /opt/app/src/backup.crontab.template > /opt/app/src/backup.crontab
exec supercronic /opt/app/src/backup.crontab
