# cpm68k for the rosco_m68k single board computer

The repository implements cpm68k on a rosco_m68k single board computer.  Features include upto 16 virtual drives on the SD Card named CPMDRIVE<letter>.IMG where letter is in the range A to P.  If less than 16 drives are used, a small Ram disk is also mounted.

The Makefile curates a set of standard disk images that can be used. These include:
- a C compiler
- a Pascal compiler
- a Forth interpreter
- a BASIC compiler
- an old version of the EMACS editor
- the cpm68k distribution 

The code has been tested on a 68010 and 68020 board as well as under th "r68k" Rosco emulator.  Under Mame there is an issue with writing to the SD Card.  Mame crashes out under load.

The main sources for the project are listed below.  The code is really a mash-up between Plasmode's work on the mpu302 and Damien Wildie's work on the S100 single board computer.

## Pre-requisites
This code was developed on a M1 MacBook Air.  Homebrew was the package manager.
- rosco_m68k development tool chain - see references.
- cpmtools - installed with `brew install cpmtools`.  Note that the homebrew code makes use of libraw and hence I had to change all of Damien's routines that use cpmtools to include the option `-T raw`. Copy the diskdefs used in the project across to the main diskdefs file after installation.  Note this the specific directory for the M1 version of homebrew .. if you are on a x86 then the directory is different .. `cat 68k-diskdefs.txt >> /opt/homebrew/share/diskdefs`.  **TO DO:** This change to the diskdefs file is only necessary to support offset partitions into a larger disk file, not sure this is really necessary .. maybe we remove this in the future. 
- mtools - installed with `brew install mtools`.  Used to create the FAT32 sdcard image used by MAME.

## Memory Map
The goal was to re-use the rosco_m68k firmware as much as possible.  cpm68k comes in two flavours - one that loads cpm at 0x400 and the other at 0x15000.  Rosco firmware reserves upto 0x2000, so the 0x15000 option is used. 

The way programs are loaded from sdcard on the rosco is as follows: the program is initially loaded to 0x40000 then relocated to 0x2000 and executed.  These address ranges had to be avoided.  The basic memory map is as follows:

- 0x0 to 0x2000 - rosco firmware
- 0x15000 - 0x1AFFF - CPM and scratch space
- 0x1B000 - 0x1BFFF - bios
- 0x20000 - 0xA0000 - CPM TPA or memory available to the user of cpm to run programs (0x80000 or 524,228 bytes)
- 0xC0000 - 0xEFFFF - RAM disk, this gives a max disk size of 131,072 bytes (0x2000)

There are some gaps in the memory map and this could be further optimised.  Note that because of the loading process, the total size of the file CPM plus bios plus ram disk image cant be more than 0x38000 (229,376 bytes) as the loaded program has to be relocated from 0x40000 to 0x2000.

## Code structure
A top level `makefile` sequentially goes through each of the following directories and builds the subprojects: 
- bios - the bios is in assember and compiled to 0x1b000, the standard location for cpm loading at 0x15000.  Creates `target/bios.sr.bin` which is loaded at 0x1B000 by the boot program.
- boot - this creates `target/boot.bin` which is a program that can be loaded directly from a sdcard or similar.  The program contains the binary files for cpm, bios and ram disk.  When the program runs it reclocates cpm code to 0x15000, the bios to 0x1B000 and the ram disk to 0xC0000.  It then calls cpm at 0x15000.
- cpmfs - this creates a CPM disk image for loading into ram, `target/cpmdisk.img`.  To load into available memory from 0xC0000 this disk is  limited in size.  At the moment it just contains a text file for the partition label and a small welcome file.
- disk - this creates a FAT32 file image `target/rosco.img` that can be saved to a sdcard or loaded into MAME.  the boot file is saved as `roscode1.bin` so that it is auto run on machine start.  The CPM disk image `cpmdisk.img` is also copied across to the sdcard image.  The last part of the makefile prints the command linkt o start MAME.  This assumes that MAME is imstalled in a directory at the same level as this project.

## Limitations
- Must be run from the sd card - doesn't support the use of an IDE drive (yet)
- Various, as yet undiscovered, bugs !

## References:
- [Details on the board](https://rosco-m68k.com/)
- [Links to documents on cpm68k and Damien Wildie's work on a S100 SBC on which this code is derived.](http://www.s100computers.com/Software%20Folder/CPM68K/CPM68K%20Software.htm)
- [Damien's github page](https://github.com/dwildie/cpm-68k)
- [Plasmodes' work on the mpu302.](https://hackaday.io/project/28504-reverse-engineering-soneplex-spx-mpu-sbc/log/71892-port-cpm-68k-to-mpu302-part-1)
- [General info, hints and tips.](https://www.retrobrewcomputers.org/forum/index.php?t=msg&th=222&goto=3703&)
- [The main source for all things cpm.](http://www.cpm.z80.de/)
- [Very useful table of ascii cocdes in hex and decimal.](https://www.ibm.com/docs/en/aix/7.2?topic=adapters-ascii-decimal-hexadecimal-octal-binary-conversion-table)
