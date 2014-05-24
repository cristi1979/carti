#!/bin/bash

# sudo python -c "import sys; py3 = sys.version_info[0] > 2; u = __import__('urllib.request' if py3 else 'urllib', fromlist=1); exec(u.urlopen('http://status.calibre-ebook.com/linux_installer').read()); main()"

make_ebook() {
  mkdir -p ./$dir
  httrack $site -O $dir --mirror '-*.pdf' '+*.png' '+*.gif' '+*.jpg' '+*.jpeg' '+*.css' '+*.js' "+*.$domain/*"
  [[ -d ./$dir/$domain/trunk ]] && rel_path="./$dir/$domain/trunk/" || rel_path="./$dir/$domain/"

  echo '
body #content{margin-top: 0px;}
#content{margin: 0px 0px 0px 0px;}
#header{display:none;}
#leftnavigation{display:none;}
#toolbar{display:none;}
#legal{display:none;}' >> ./$rel_path/*/common/css/custom.css || exit 2

  ~/programe/calibre/ebook-convert ./$rel_path/*/content/index.html ./$dir.epub --minimum-line-height=0 --smarten-punctuation --level1-toc="//h:h1" --level2-toc="//h:h2" --level3-toc="//h:h3" --chapter="//*[name()='h1' or name()='h2' or name()='h3']" --input-profile=default --output-profile=nook --use-auto-toc --title=$dir --authors=openstack || exit 3
}

domain="docs.openstack.org"

site="http://docs.openstack.org/trunk/openstack-ops/content/section_yk2_jpr_lj.html"
dir=openstack_ops
make_ebook &

site="http://docs.openstack.org/high-availability-guide/content/ch-intro.html"
dir=openstack_high_availability
make_ebook &

site="http://docs.openstack.org/trunk/config-reference/content/config_overview.html"
dir=openstack_conf
make_ebook &

site="http://docs.openstack.org/admin-guide-cloud/content/ch_getting-started-with-openstack.html"
dir=openstack_admin_guide
make_ebook &

# python << END
# from BeautifulSoup import BeautifulSoup
# soup = BeautifulSoup(open("./content/index.html",'r').read())
# >>> elem = soup.findAll('a', {'title': 'title here'})
# >>> elem[0].text
# END
