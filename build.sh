#!/bin/bash
gcc -std=c99 -o genconfig genconfig.c
gcc -std=c99 -o getFirstInteger getFirstInteger.c
gcc -std=c99 -o permuteInputs permuteInputs.c
gcc -std=c99 -o area area.c -lm

echo Generating permutations.
./permuteInputs > inputs.txt
