#!/bin/sh

# increase file descriptor limit
echo 65535 > /proc/sys/fs/file-max
ulimit -n unlimited
