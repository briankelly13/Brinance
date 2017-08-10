all:
	echo "No 'all'. This just installs brinance."

install:
	install -d ~/.brinance/lib/
	install -d ~/bin/
	install --mode=555 brinance ~/bin/
	install --mode=444 Brinance.pm ~/.brinance/lib/

