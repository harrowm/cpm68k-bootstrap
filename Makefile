# SUBDIRS := bios cpmfs boot
SUBDIRS := bios boot disk


clean all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)
	
.PHONY: clean all $(SUBDIRS)
