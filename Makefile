# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
clean:
	find . -name \*\~ -print0 | xargs -0 rm -f
	-zsh -c 'etags tiarra tiarra-conf.el tiarra-conf.l main/**/*.pm module/**/*.pm'

update:
	cvs -z 5 -q up -dP
	./makedoc

DIFF_PATH :=
VENDOR_MASTER := ../vendor/cvs/master
VENDOR_WORKING := ../vendor/cvs/working

checkdiff:
	-LANG=C diff -rub -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

diff:
	-LANG=C diff -ru -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

working_install:
	cp ./$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_start:
	-rm -rf $(VENDOR_WORKING)/$(DIFF_PATH)
	cp -a $(VENDOR_MASTER)/$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_checkdiff:
	-LANG=C diff -rub -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

working_diff:
	-LANG=C diff -ru -F'^[a-zA-Z]' -I Clovery: -I Id: -x CVS -x .svn $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

