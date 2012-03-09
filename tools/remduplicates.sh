#!/bin/bash
OUTF=rem-duplicates.sh;
echo "#! /bin/sh" > $OUTF;
echo "" >> $OUTF;
find "$@" -type f -exec md5sum {} \; |
    sort --key=1,32 | uniq -w 32 -d --all-repeated=separate |
    sed -r 's/^[0-9a-f]*( )*//;s/([^a-zA-Z0-9./_-])/\\\1/g;s/(.+)/#rm \1/' >> $OUTF;
chmod a+x $OUTF; ls -l $OUTF

# gawk 'BEGIN { RS = "" ; FS = "\n" }{for (i=2;i<=NF;i++)print $i" /tmp/coco1"}' $OUTF | sed s/^#rm/mv/ > ./rmall.sh
gawk 'BEGIN { RS = "" ; FS = "\n" }{for (i=2;i<=NF;i++)print $i}' $OUTF  | sed s/^#rm/rm\ -f/ > ./rmall.sh
rm $OUTF
echo "find \"$@\" -depth -type d -empty -exec rmdir {} \;" >> ./rmall.sh
