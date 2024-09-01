#!/bin/sh

set -e

PROJECT=main

ALEF=$HOME/Projects/alef-plan9port
PATH=$ALEF/bin:$PATH; export PATH

8al -o $PROJECT.o -I$ALEF/include/alef main.l
8l -o $PROJECT -L $ALEF/lib/alef $PROJECT.o -lA
brandelf -t FreeBSD $PROJECT
rm $PROJECT.o
