ROSCO_M68K_DIR=~/rosco_m68k

ifndef ROSCO_M68K_DIR
$(error Please set ROSCO_M68K_DIR to the top-level rosco_m68k directory to use for rosco_m68k building)
endif

-include $(ROSCO_M68K_DIR)/user.mk

AS       = m68k-elf-as
ASFLAGS += -m68000
ASFLAGS += -alms
ASFLAGS += --defsym IS_68000=1

CC       = m68k-elf-gcc
CCFLAGS += -Wall
CCFLAGS += -m68000
CCFLAGS += -nostdlib
CCFLAGS += -nodefaultlibs

DEFINES=-DROSCO_M68K
VASM=vasmm68k_mot
VASMFLAGS=-Felf -m68010 -quiet -Lnf $(DEFINES)

SYSINCDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/include
SYSLIBDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/lib

ifneq ($(ROSCO_M68K_HUGEROM),false)
LDSCRIPT?=$(SYSLIBDIR)/ld/serial/hugerom_rosco_m68k_program.ld
else
LDSCRIPT?=$(SYSLIBDIR)/ld/serial/rosco_m68k_program.ld
endif

GCC_LIBS=$(shell $(CC) --print-search-dirs 															\
	| grep libraries:\ =		\
	| sed 's/libraries: =/-L/g' 	\
	| sed 's/:/m68000\/ -L/g')m68000/

LD       = m68k-elf-ld
LD       = m68k-elf-ld
LDFLAGS   = -L $(SYSLIBDIR) --gc-sections #--oformat=elf32-m68k
LDFLAGS  += $(GCC_LIBS)

LIBS	  = -lrosco_m68k
LIBS	 += -lsdfat
LIBS     += -lgcc



all: target/bios.sr.bin #target/bios.srec

%.s:	%.c
	$(CC) $(CCFLAGS) -S $<

# --------------------------------------------------------------------------------
# M68K CPM Bios
# --------------------------------------------------------------------------------

obj/%.o: %.asm | obj
	$(VASM) $(VASMFLAGS) -L $(basename $@).lst -o $@ $<

obj/bios.srec: obj/bios.o | obj
	$(LD) -T bios.lnk $(LDFLAGS) obj/bios.o -Map $(@:.srec=.map) $(LIBS) -o $@

target/bios.srec: obj/bios.srec | target
	srec_cat $< -fill 0x00 -over $< -header="CP/M-68K rosco_m68k BIOS V0.1" -o $@
	srec_info $@

target/bios.sr.bin: target/bios.srec | target
	m68k-elf-objcopy -I srec -O binary target/bios.srec target/bios.sr.bin

clean:
	rm -rf obj/* target/*

obj:
	mkdir -p $@

target:
	mkdir -p $@

