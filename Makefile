# -----------------------------------------------------------------------------
# Makefile which deletes all backup files made by Emacs.
# -----------------------------------------------------------------------------
# $Id: Makefile,v 1.4 2004/03/13 07:17:33 admin Exp $
# -----------------------------------------------------------------------------
all:
	find . -name \*\~ -print0 | xargs -0 rm -f
	gtags

update:
	cvs -z 5 -q up -dP
	./makedoc

DIFF_PATH :=
VENDOR_MASTER := ../vendor/cvs/master
VENDOR_WORKING := ../vendor/cvs/working

checkdiff:
	-diff -rub -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

diff:
	-diff -ru -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

working_install:
	cp ./$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_start:
	-rm -rf $(VENDOR_WORKING)/$(DIFF_PATH)
	cp -a $(VENDOR_MASTER)/$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_checkdiff:
	-diff -rub -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

working_diff:
	-diff -ru -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

