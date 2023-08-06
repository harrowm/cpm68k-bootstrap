# cpm68k-bootstrap
Bootstrapping cpm68k into memory on a rosco_m68k single board computer ...

After trying for a while to modify a bios written in 68000 machine code, I thought I would stop and try to get a basic cmp68k up and running with a bios in C.  My C is much better than my 68000 machine code skills ..

brew install cpmtools
cat 68k-diskdefs.txt >> /opt/homebrew/share/diskdefs
.. this is for a M1 MAc, for a x86 Mac/Linux the home brew install directory is different 

The basic idea is to follow the steps used by Plasmode to set up cpm68k on his 68k board and leverage Damien Wildie's excellent work for his board.

Interesting links:

Details on the board: https://rosco-m68k.com/

Links to documents on cpm68k and David Wildie's work on a S100 SBC on which this code is derived. http://www.s100computers.com/Software%20Folder/CPM68K/CPM68K%20Software.htm https://github.com/dwildie/cpm-68k

https://hackaday.io/project/28504-reverse-engineering-soneplex-spx-mpu-sbc/log/71892-port-cpm-68k-to-mpu302-part-1

General info, hints and tips: https://www.retrobrewcomputers.org/forum/index.php?t=msg&th=222&goto=3703&

The main source for all things cpm: http://www.cpm.z80.de/

