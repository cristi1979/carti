#!/bin/bash

here_dir=$(pwd)
find ./ -type f -iname CDImage.ape.cue | while read FILENAME; do
   dir=$(readlink -f "$(dirname "$FILENAME")");
   echo XXXXXXXXXXXXXXXXXXXXXX working in $dir;
   cd "$dir";
   mv CDImage.ape.cue CDImage.ape.cue.ascii;
   iconv -f WINDOWS-1252 -t utf-8 CDImage.ape.cue.ascii -o CDImage.ape.cue;
   mkdir -p split;
   shnsplit -d split -f CDImage.ape.cue -o "flac flac -V --best -o %f -" CDImage.ape -t "%n %p - %t";
   #ffmpeg -i CDImage.ape CDImage.wav
   #bchunk -w CDImage.wav CDImage.ape.cue BASE_FILENAME
   #flac BASE_FILENAME* -V --best
   rename 's/ /_/g' "split/"*.flac;
   cuetag CDImage.ape.cue "split/"*.flac;
   rename 's/_/ /g' "split/"*.flac;
   rm -f CDImage.ape.cue;
   mv CDImage.ape.cue.ascii CDImage.ape.cue;
   cd "$here_dir";
done
