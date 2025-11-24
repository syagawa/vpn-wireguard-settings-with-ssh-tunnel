#!/bin/sh
apk add --no-cache nginx
mkdir -p /run/nginx
touch /run/nginx/nginx.pid
nginx -g 'daemon off;' -c /etc/nginx/nginx.conf