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
IGNORES := $(IGNORES) -I Clovery: -I Id:
IGNORES := $(IGNORES) -x CVS -x .svn -x common -x test -x \*~ -x TAGS
IGNORES := $(IGNORES) -x Makefile -x .tiarrarc -x doc -x filelist.\*
IGNORES := $(IGNORES) -x web -x sample.conf -x run\* -x status
IGNORES := $(IGNORES) -x think -x tools
IGNORES := $(IGNORES) -x \*.\*.jp -x \*.ath.cx -x local -x stable

checkdiff:
	-LANG=C diff -burN -F'^[a-zA-Z]' $(IGNORES) $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

diff:
	-LANG=C diff -urN -F'^[a-zA-Z]' $(IGNORES) $(VENDOR_MASTER)/$(DIFF_PATH) ./$(DIFF_PATH)

working_install:
	cp ./$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_start:
	-rm -rf $(VENDOR_WORKING)/$(DIFF_PATH)
	cp -a $(VENDOR_MASTER)/$(DIFF_PATH) $(VENDOR_WORKING)/$(DIFF_PATH)

working_checkdiff:
	-LANG=C diff -burN -F'^[a-zA-Z]' $(IGNORES) $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

working_diff:
	-LANG=C diff -urN -F'^[a-zA-Z]' $(IGNORES) $(VENDOR_WORKING)/$(DIFF_PATH) ./$(DIFF_PATH)

