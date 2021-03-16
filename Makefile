test:
	dzil test

tidy:
	dzil perltidy && git checkout -- Makefile.PL
