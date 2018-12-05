#!/bin/bash
gcc -o genconfig genconfig.c
gcc -o getFirstInteger getFirstInteger.c
gcc -o permuteInputs permuteInputs.c

echo Generating permutations.
./permuteInputs > inputs.txt
