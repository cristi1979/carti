
#sudo apt-get install python-bs4
from bs4 import BeautifulSoup
soup = BeautifulSoup(html_doc)
[s.extract() for s in soup(['iframe', 'script'])]
## keep chapter div class
