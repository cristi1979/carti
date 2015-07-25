#!/bin/bash
INDEX_FILE=index
DIR=$(readlink -f $1)
TMP_DIR_Q="$DIR/tmp"

while IFS= read -r FILE; do
  echo $FILE
  filedir=$(dirname "$FILE")
  filename=$(basename "$FILE")
  full_filename=$filename
  extension=${filename##*.}
  filename=${filename%.*}
  fileauthor=$(dirname "$filedir")
  echo $fileauthor $filedir $FILE

  TMP_DIR="$(echo $TMP_DIR_Q/$filename | sed s/\,//g)"
  full_filename=$(echo $full_filename | sed s/\,//g)
  filename=$(echo $filename | sed s/\,//g)
  mkdir -p "$TMP_DIR"
  cp "$FILE" "$TMP_DIR/$full_filename"
  ~/programe/calibre/ebook-convert "$TMP_DIR/$filename.$extension" "$TMP_DIR/$filename.htmlz" --no-chapters-in-toc --toc-threshold=0 --max-toc-links=0 --htmlz-css-type=tag --htmlz-class-style=inline
  cd "$TMP_DIR"
  unzip "$filename.htmlz"
  echo "make odt"
  libreoffice --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter($TMP_DIR/index.html)" || exit 1
  #libreoffice3.6 --writer --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter($TMP_DIR/index.html)"
  mv "$TMP_DIR/index.odt" "$TMP_DIR/$filename.odt"
  rm "$TMP_DIR/$filename.$extension"
  mv "$FILE" "$filedir/$filename"_orig."$extension"
  mv "$TMP_DIR/$filename.odt" "$filedir"
# exit 1
done < <(find "$DIR" -iname \*.epub -o -iname \*.mobi -maxdepth 1)

# ~/programe/calibre/ebook-convert "$DIR/$INDEX_FILE.html" "$DIR/$INDEX_FILE.htmlz" --no-chapters-in-toc --toc-threshold=0 --max-toc-links=0 --htmlz-css-type=tag --htmlz-class-style=inline

# mkdir "$DIR"/htmlz
# cp "$DIR/$INDEX_FILE.htmlz" "$DIR"/htmlz
# cd "$DIR"/htmlz
# unzip -o "$INDEX_FILE.htmlz"

# ~/programe/carti/cleaners/aaa_collection.sh /media/ceva1/Audio/Carti/ac_noi/ac_noi.zip
# ~/programe/carti/cleaners/clean_html.pl /media/ceva1/Audio/Carti/ac_noi/htmlz/index.html
# libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/media/ceva1/Audio/Carti/ac_noi/htmlz/index.html.html)"
