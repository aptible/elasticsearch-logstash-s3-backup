FROM quay.io/aptible/alpine:latest
RUN apk update && apk-install coreutils curl
ADD . /opt/app
WORKDIR /opt/app/src
CMD ["/bin/bash"]