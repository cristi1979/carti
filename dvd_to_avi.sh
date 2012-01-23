#!/bin/bash

for FILE in "DVD01" "DVD02" "DVD03" "DVD04" "DVD05" "DVD06" "DVD07" "DVD08" "DVD09" "DVD10" "DVD11" "DVD12"; do
  echo $FILE;
  for I in {3..25}; do
    echo $I;
    mencoder -aid 128 dvd://$I -dvd-device "$FILE" -idx -ovc copy -oac copy -o $FILE\_$I.avi
  done
done
