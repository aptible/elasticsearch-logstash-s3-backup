FROM quay.io/aptible/alpine:latest
RUN apk update && apk-install curl
ADD elasticsearch-backup.crontab /opt/elasticsearch-backup.crontab
RUN crontab /opt/elasticsearch-backup.crontab
ADD src/ /opt/script
CMD ["/bin/bash"]