#!/bin/bash

filename=$1
while read p; do
	in = ${p}
	cat ${in[0]} ${in[1]} ${in[2]} ${in[3]} ${in[4]} ${in[5]} ${in[6]} ${in[7]} ${in[8]}
	#genconfig ${in[0]} ${in[1]} ${in[2]} ${in[3]} ${in[4]} ${in[5]} ${in[6]} ${in[7]} ${in[8]} > foo.txt
done < $filename