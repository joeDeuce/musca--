#!/bin/bash

# eg, regenerate proto.h
if [ $1 == 'dump' ]; then
	cat $2 | grep -e '^[a-z]' | sed s/$/\;/
fi

# look for orphans
if [ $1 == 'counts' ]; then
	cat musca_proto.h | awk '{print $2}' | awk -F '(' '{print $1; system("grep -c " $1 " musca.c");}'
fi
