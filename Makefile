all:
	echo "No 'all'. This just installs brinance."

install:
	mkdir -p ~/.brinance/lib/
	mkdir -p ~/bin/
	cp -f brinance ~/bin/
	cp -f Brinance.pm ~/.brinance/lib/
	chmod 555 ~/bin/brinance
	chmod 444 ~/.brinance/lib/Brinance.pm

