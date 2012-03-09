#!/bin/bash
INDEX_FILE=index
FILE=$1
DIR=$(dirname "$FILE")
filename=$(basename "$FILE")
extension=${filename##*.}
filename=${filename%.*}

cd "$DIR"
unzip -o "$FILE"

echo '<html>' >> "$DIR/$INDEX_FILE.html"
echo '   <body>' >> "$DIR/$INDEX_FILE.html"
echo '     <h1>Table of Contents</h1>' >> "$DIR/$INDEX_FILE.html"
echo '     <p style="text-indent:0pt">' >> "$DIR/$INDEX_FILE.html"
# nr=1
while IFS= read -r file; do
    if [ "$file" != "$DIR/$INDEX_FILE.html" ]; then
      echo '    <a href="'$file'">File '$file'</a><br/>' >> "$DIR/$INDEX_FILE.html"
    fi
done < <(ls "$DIR"/*.html "$DIR"/*.htm)

echo '     </p>' >> "$DIR/$INDEX_FILE.html"
echo '   </body>' >> "$DIR/$INDEX_FILE.html"
echo '</html>' >> "$DIR/$INDEX_FILE.html"

~/programe/calibre/ebook-convert "$DIR/$INDEX_FILE.html" "$DIR/$INDEX_FILE.htmlz" --no-chapters-in-toc --toc-threshold=0 --max-toc-links=0 --htmlz-css-type=tag --htmlz-class-style=inline

mkdir "$DIR"/htmlz
cp "$DIR/$INDEX_FILE.htmlz" "$DIR"/htmlz
cd "$DIR"/htmlz
unzip -o "$INDEX_FILE.htmlz"

# ~/programe/carti/cleaners/clean_liternet_zip.sh /media/ceva1/Audio/Carti/ac_noi/ac_noi.zip
# ~/programe/carti/cleaners/clean_liternet_html.pl /media/ceva1/Audio/Carti/ac_noi/htmlz/index.html
# libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/media/ceva1/Audio/Carti/ac_noi/htmlz/index.html.html)"
