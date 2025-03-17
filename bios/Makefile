ROSCO_M68K_DIR=~/rosco_m68k

ifndef ROSCO_M68K_DIR
$(error Please set ROSCO_M68K_DIR to the top-level rosco_m68k directory to use for rosco_m68k building)
endif

-include $(ROSCO_M68K_DIR)/user.mk

DEFINES=-DROSCO_M68K
VASM=vasmm68k_mot
VASMFLAGS=-Felf -m68010 -quiet -Lnf $(DEFINES)

SYSINCDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/include
SYSLIBDIR?=$(ROSCO_M68K_DIR)/code/software/libs/build/lib

LD       = m68k-elf-rosco-ld
LDFLAGS   = -L $(SYSLIBDIR) --gc-sections

LIBS	  = -lrosco_m68k

all: target/bios.sr.bin #target/bios.srec

%.s:	%.c
	$(CC) $(CCFLAGS) -S $<

obj/%.o: %.asm | obj
	$(VASM) $(VASMFLAGS) -L $(basename $@).lst -o $@ $<

obj/bios.srec: obj/bios.o | obj
	$(LD) -T bios.lnk $(LDFLAGS) obj/bios.o -Map $(@:.srec=.map) $(LIBS) -o $@

target/bios.srec: obj/bios.srec | target
	srec_cat $< -fill 0x00 -over $< -header="CP/M-68K rosco_m68k BIOS V0.1" -o $@
	srec_info $@

target/bios.sr.bin: target/bios.srec | target
	m68k-elf-rosco-objcopy -I srec -O binary target/bios.srec target/bios.sr.bin

clean:
	rm -rf obj/* target/*

obj:
	mkdir -p $@

target:
	mkdir -p $@

