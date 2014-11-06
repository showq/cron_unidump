#!/bin/bash

for a in $HOME/scripts/*.gz ; do
  CLEAR=${a#*/scripts/}
  echo ${CLEAR%%.gz}

done
