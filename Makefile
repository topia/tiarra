# -----------------------------------------------------------------------------
# Makefile which deletes all backup files made by Emacs.
# -----------------------------------------------------------------------------
# $Id: Makefile,v 1.3 2003/06/03 15:27:43 admin Exp $
# -----------------------------------------------------------------------------
all:
	-zsh -c 'rm -f **/*~'
	-zsh -c 'etags tiarra tiarra-conf.el tiarra-conf.l main/**/*.pm module/**/*.pm'

update:
	cvs -z 5 -q up -dP

DIFF_PATH :=
VENDOR_MASTER := ../vendor/cvs/master
VENDOR_WORKING := ../vendor/cvs/working

checkdiff:
	-diff -rub -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

diff:
	-diff -ru -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

working:
	cp ./$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)
