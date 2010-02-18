#!/bin/sh

# increase file descriptor limit
echo 65535 > /proc/sys/fs/file-max
ulimit -n 65536
/etc/init.d/rabbitmq-server restart
