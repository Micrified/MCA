#!/bin/bash


if [ "$1" ] && [ "$2" ]; then

	filename=$1
	program=$2

	# For all lines in the input file ...
	while read p; do

		# Split input line into individual parameters.
		in=($p)

		# Assign each input parameter to a variable.
		a=${in[0]}
		b=${in[1]}
		c=${in[2]}
		d=${in[3]}
		e=${in[4]}
		f=${in[5]}
		g=${in[6]}
		h=${in[7]}
		i=${in[8]}

		# Add the configuration to the results file.
		printf "%s %s %s %s %s %s %s %s %s " "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h" "$i" >> results.txt

		# Generate the configuration file for run.
		./genconfig a b c d e f g h i > configurations.mm

		# Run the program (it will generate results in a folder).
		run $program -O3

		# Get cycle count from the results file and append.
		./getFirstInteger < output-$program.c/ta.log.000 >> results.txt
	done < $filename

else
	echo "Run with input: <permutation-file> <program-name>"
	exit 1
fi
