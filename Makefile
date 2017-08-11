all:
	@echo -e "Nothing to make. This just installs brinance.\nRun 'make install'."

install:
	install -d ~/.brinance/lib/
	install -d ~/bin/
	install --mode=755 brinance ~/bin/
	install --mode=644 Brinance.pm ~/.brinance/lib/

