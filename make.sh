#!/bin/sh

set -e

PROJECT=main

ALEF=$HOME/Projects/alef-plan9port
PATH=$ALEF/bin:$PATH; export PATH

for file in `ls *.l`; do
	8al -o $file.o -I$ALEF/include/alef $file
done

8l -o $PROJECT -L $ALEF/lib/alef *.o -lA
brandelf -t FreeBSD $PROJECT

rm *.o
