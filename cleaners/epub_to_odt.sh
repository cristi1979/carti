#!/bin/bash
INDEX_FILE=index
DIR=$1
TMP_DIR_Q="/media/ceva1/Audio/Carti/ac_noi"

while IFS= read -r FILE; do
  echo $FILE
  filedir=$(dirname "$FILE")
  filename=$(basename "$FILE")
  extension=${filename##*.}
  filename=${filename%.*}
  fileauthor=$(dirname "$filedir")
  echo $fileauthor $filedir $FILE

  TMP_DIR="$TMP_DIR_Q/$filename"
  mkdir -p "$TMP_DIR"
  cp "$FILE" "$TMP_DIR"
  ~/programe/calibre/ebook-convert "$TMP_DIR/$filename.$extension" "$TMP_DIR/$filename.htmlz" --no-chapters-in-toc --toc-threshold=0 --max-toc-links=0 --htmlz-css-type=tag --htmlz-class-style=inline
  cd "$TMP_DIR"
  unzip "$TMP_DIR/$filename.htmlz"
  libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter($TMP_DIR/index.html)"
  mv "$TMP_DIR/index.odt" "$TMP_DIR/$filename.odt"
  rm "$TMP_DIR/$filename.$extension"
  mv "$FILE" "$filedir/$filename"_orig."$extension"
  mv "$TMP_DIR/$filename.odt" "$filedir"
# exit 1
done < <(find "$DIR" -iname \*.epub)

# ~/programe/calibre/ebook-convert "$DIR/$INDEX_FILE.html" "$DIR/$INDEX_FILE.htmlz" --no-chapters-in-toc --toc-threshold=0 --max-toc-links=0 --htmlz-css-type=tag --htmlz-class-style=inline

# mkdir "$DIR"/htmlz
# cp "$DIR/$INDEX_FILE.htmlz" "$DIR"/htmlz
# cd "$DIR"/htmlz
# unzip -o "$INDEX_FILE.htmlz"

# ~/programe/carti/cleaners/aaa_collection.sh /media/ceva1/Audio/Carti/ac_noi/ac_noi.zip
# ~/programe/carti/cleaners/clean_html.pl /media/ceva1/Audio/Carti/ac_noi/htmlz/index.html
# libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/media/ceva1/Audio/Carti/ac_noi/htmlz/index.html.html)"
