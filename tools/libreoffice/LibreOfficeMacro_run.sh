rm -rf ~/.libreoffice/
libreoffice --headless --invisible --nodefault --nologo --nofirststartwizard --norestore --convert-to swriter /dev/null
cp /home/cristi/programe/scripts/carti/tools/libreoffice/Standard/* ~/.libreoffice/3/user/basic/Standard/
libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/home/cristi/programe/scripts/carti/qq/index.html)"

libreoffice --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.ReplaceNBHyphen(/home/cristi/Untitled 2.odt)"
