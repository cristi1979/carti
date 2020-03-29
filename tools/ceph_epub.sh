#!/bin/bash

# sudo python -c "import sys; py3 = sys.version_info[0] > 2; u = __import__('urllib.request' if py3 else 'urllib', fromlist=1); exec(u.urlopen('http://status.calibre-ebook.com/linux_installer').read()); main()"

make_ebook() {
  mkdir -p ./$dir
  httrack $site -O $dir --mirror '-*.pdf' '+*.png' '+*.gif' '+*.jpg' '+*.jpeg' '+*.css' '+*.js' "+$site/docs/master/*"
  rm -rf ./$dir/$domain/docs/master/_static/font/
#   wget --directory-prefix=$dir --recursive --page-requisites --html-extension --convert-links --domains $domain --no-parent -R *.pdf -nH $site
#   rm -rf ./$dir/docs/master/_static/font/

  echo '
.sphinxsidebar {display:none;}
.related {display:none;}
.footer {display:none;}
div.bodywrapper{margin: 0px 0px 0px 0px;}
div.documentwrapper{float:none;width: auto;}
div.body {padding: 0px 0px 0px;}
body {border-top: 0px;}'>> ./$dir/$domain/docs/master/_static/nature.css || exit 2

#   ~/programe/calibre/ebook-convert ./$dir/$domain/docs/master/*/*/index.html ./$dir.htmlz
  ~/programe/calibre/ebook-convert ./$dir/$domain/docs/master/*/index.html ./$dir.epub --minimum-line-height=0 --smarten-punctuation --level1-toc="//h:h1" --level2-toc="//h:h2" --level3-toc="//h:h3" --chapter="//*[name()='h1' or name()='h2' or name()='h3']" --input-profile=default --output-profile=nook --use-auto-toc --title=$dir --authors=ceph || exit 3
}

domain="ceph.com"

site="http://ceph.com/docs/master/install/"
dir=ceph_install
make_ebook &

site="http://ceph.com/docs/master/rados/"
dir=ceph_rados
make_ebook &

site="http://ceph.com/docs/master/cephfs/"
dir=ceph_cephfs
make_ebook &

site="http://ceph.com/docs/master/radosgw/"
dir=ceph_radosgw
make_ebook &

site="http://ceph.com/docs/master/architecture/"
dir=ceph_architecture
make_ebook &

site="http://ceph.com/docs/master/dev/"
dir=ceph_dev
make_ebook &

site="http://ceph.com/docs/master/rbd/"
dir=ceph_rbd
make_ebook &
