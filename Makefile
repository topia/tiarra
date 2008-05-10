# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
update:
	svn up
	./makedoc

clean:
	find . \( -type d \( -name main -o -name module \) -prune -o -true \) -name \*\~ -print0 | xargs -0 rm -fv
	-zsh -c 'etags tiarra tiarra-conf.el tiarra-conf.l main/**/*.pm module/**/*.pm'

