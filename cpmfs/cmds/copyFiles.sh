#!/bin/bash

usage() {
  echo "Usage: $0 <image_file> <disk-def> <file1> ..."
}

if [ $# -lt 3 ]; then
  usage
  exit 1
fi

IMAGE=$1
DEF=$2

args=("$@")

n=2
while [ $n -lt $# ]
do
  echo "Copying ${args[$n]} to $IMAGE, definition $DEF"
  cpmcp -T raw -t -f ${DEF} $IMAGE ${args[$n]} 0:
  
  n=$(( $n + 1))
done
