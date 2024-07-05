There is a CPM68k simulator here:
http://davesrocketworks.com/electronics/cpm68/simulator.html

that includes a very interesting disk image with a working forth and emacs, some discussion on it here:

https://www.retrobrewcomputers.org/forum/index.php?t=msg&th=254&prevloaded=1&&start=80

This directory contains the cpm filesystem image.  The disk definition thats needs to be added to diskdefs is:

diskdef sim
seclen 128
tracks 512
sectrk 256
blocksize 2048
maxdir 4096
skew 0
boottrk 1
os 2.2
end
  

Malcolm Harrow June 24, 2024
