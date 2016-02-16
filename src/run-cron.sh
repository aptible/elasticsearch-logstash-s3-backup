#!/bin/bash
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 2 * * *"}
sed "s:CRON_SCHEDULE:${CRON_SCHEDULE}:g" /opt/app/src/backup.crontab.template > /opt/app/src/backup.crontab
env > /opt/app/src/app.env
crontab /opt/app/src/backup.crontab
touch /var/log/cron.log
crond
tail -f /var/log/cron.log
