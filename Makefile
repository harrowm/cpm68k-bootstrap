# SUBDIRS := bios cpmfs boot
SUBDIRS := bios cpmfs boot disk


clean all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)
	
.PHONY: clean all $(SUBDIRS)
