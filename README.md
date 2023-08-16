# cpm68k-bootstrap
Bootstrapping cpm68k into memory on a rosco_m68k single board computer ...

This bios boots cpm68k on the rosco_m68k single board computer.  Its a very minimal bios, written in assmebler and using a single small RAM disk.  The code has been tested under MAME - it has not (yet) been tested against real hardware.

The main sources for the project are listed below.  The code is really a amash-up between Plasmode work on the mpu302 and Damien Wildie's work on the S100 single board computer.

## Pre-requisites
This code was developed on a M1 MacBook Air.  Homebrew was the package manager.
- rosco_m68k development tool chain - see references.
- MAME - see references (to do, explain MAME patch to get SDCARD working, explain machine specific file).
- cpmtools - installed with `brew install cpmtools`.  Note that the homebrew code makes use of libraw and hence I had to change all of Damien's routines that use cpmtools to include the option `-T raw`. Copy the diskdefs used in the project across to the main diskdefs file after installation.  Note this the specific directory for the M1 version of homebrew .. if you are on a x86 then the direwctory is different .. `cat 68k-diskdefs.txt >> /opt/homebrew/share/diskdefs`
- mtools - installed with `brew install mtools`.  Used to create the FAT32 sdcard image used by MAME.

## Memory Map
The goal was to re-use the rosco_m68k firmware as much as possible.  cpm68k comes in two flavours - one that loads cpm at 0x400 and the other at 0x15000.  Rosco firmware reserves upto 0x2000, so the 0x15000 option is used. 

The way programs are loaded from sdcard on the rosco is as follows: the program is initially loaded to 0x40000 then relocated to 0x2000 and executed.  These address ranges had to be avoided.  The basic memory map is as follows:

- 0x0 to 0x2000 - rosco firmware
- 0x15000 - 0x1AFFF - cpm and scratch space
- 0x1b000 - 0x1BFFF - bios, actually the bios is less than 1k at the moment
- 0x1C000 - 0xA0000 - cpm TPA or memory available to the user of cpm to run programs (0x84000 or 540,672 bytes)
- 0xC0000 - 0xFFFFF - RAM disk, this gives a max disk size of 16383 bytes (0x3FFF)

There are some gaps in the memory map and this could be further optimised.  Note that because of the loading process, the total size of the file cpm plus bios plus ram disk image cant be more thasn 0x38000 (229,376 bytes) as the loaded program has to be relocated from 0x40000 to 0x2000.

## Code structure
- top level makefile 
- bios - the bios is in assember and compiled to 0x1b000, the standard 
- boot
- cpmfs
- disk

## References:
- [Details on the board](https://rosco-m68k.com/)
- Links to documents on cpm68k and David Wildie's work on a S100 SBC on which this code is derived. http://www.s100computers.com/Software%20Folder/CPM68K/CPM68K%20Software.htm https://github.com/dwildie/cpm-68k
- Plasmodes' work on the mpu302. https://hackaday.io/project/28504-reverse-engineering-soneplex-spx-mpu-sbc/log/71892-port-cpm-68k-to-mpu302-part-1
- General info, hints and tips: https://www.retrobrewcomputers.org/forum/index.php?t=msg&th=222&goto=3703&
- The main source for all things cpm: http://www.cpm.z80.de/
- Very useful table of ascii cocdes in hex and decimal: https://www.ibm.com/docs/en/aix/7.2?topic=adapters-ascii-decimal-hexadecimal-octal-binary-conversion-table

