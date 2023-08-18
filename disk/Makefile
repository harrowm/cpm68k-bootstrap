target/rosco.img: ../boot/target/boot.bin | target
	# Create a 64Mb FAT32 disk and copy in the files
	# brew install mtools
	cp ../boot/target/boot.bin files/roscode1.bin
	dd if=/dev/zero of=target/rosco.img  bs=1M count=64
	mformat -i target/rosco.img -F :: 
	mcopy -i target/rosco.img files/* ::
	echo 'cut and paste one of these'
	echo 'cd ~/mame && ./mame roscom68k -hard1 ../cpm68k-bootstrap/disk/target/rosco.img -log -oslog -debug'
	
clean:
	rm -rf target/* files/roscode1.bin

obj:
	mkdir -p $@

target:
	mkdir -p $@
