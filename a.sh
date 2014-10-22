#!/bin/bash
HOSTID=$1
CONF=$2
INFO=`cat $CONF \
| grep -v ^$ \
 | sed -n "s/\s\+//;/\[${HOSTID}\]/,/^\[/p" \
  | grep -v ^'\[' ` && eval "$INFO"

echo $host
echo $name
echo $pass
echo $type
