#!/bin/bash

mktorrent -a $(cat ~/programe/carti/tools/torrent.trackers | gawk '{if ($1 && NR>1){printf ","$1}else{printf $1}}') -l 23 -t 6 /media/Media/Carti/Carti\ romana/
