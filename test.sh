#!/bin/bash

if  [ -d ./conf ]; then
  echo 'Have conf directory'
else
  echo 'Dont have conf directory'
fi

for f in "./conf/*"
do
  # echo $f
  cat $f \
  | grep -v ^$ \
   | sed -n "s/\s\+//;/\[${HOSTID}\]/,/^\[/p" \
    | grep -v ^'\['

  echo $HOST
done


exit
