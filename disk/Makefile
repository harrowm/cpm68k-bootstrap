#target/rosco.img: ../boot/target/boot.bin | target
	# Create a 64Mb FAT32 disk and copy in the files
	# brew install mtools

#	cp ../boot/target/boot.bin files/roscode1.bin
	
	# why is this copy here - to test what happens if a file is on the directory before CMPDISK.IMG 
	# this didn't initially work :o	
#	cp ../boot/target/boot.bin files/boot.bin
#	cp files/sdfat_menu.bin files/roscode1.bin

#	cp ../cpmfs/target/disk2.img files/CPMDISK.IMG
#	dd if=/dev/zero of=target/rosco.img  bs=1M count=64
#	mformat -i target/rosco.img -F :: 
#	mcopy -i target/rosco.img files/* ::
#	echo 'cut and paste this to run'
#	echo 'cd ~/mame && ./mame roscom68k -hard1 ../cpm68k-bootstrap/disk/target/rosco.img -log -oslog -debug'

all:
	cp ../boot/target/boot.bin ~/mame/disk/files
	cp ../cpmfs/target/cpmdisk*.img ~/mame/disk/files/

	cp ../boot/target/boot.bin ~/rosco_m68k/code/tools/r68k
	cp ~/rosco_m68k/code/software/**/*.bin ../disk/files
	cp ../cpmfs/target/cpmdisk* files

	# Create a 64Mb FAT32 disk and copy in the files
	# brew install mtools
	rm -f rosco_sd.bin
	dd if=/dev/zero of=rosco_sd.bin  bs=1M count=64
	mformat -i rosco_sd.bin -F :: 
	mcopy -i rosco_sd.bin files/* ::
	mv rosco_sd.bin ~/rosco_m68k/code/tools/r68k

	
clean:
	rm -rf target/* files/roscode1.bin

obj:
	mkdir -p $@

target:
	mkdir -p $@
