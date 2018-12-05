#!/bin/bash


if [ "$1" ] && [ "$2" ] && [ "$3" ]; then

	filename=$1
	program1=$2
	program2=$3

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
		./genconfig $a $b $c $d $e $f $g $h $i > configuration.mm

		# Run the program (it will generate results in a folder).
		run $program1 -O3
		run $program2 -O3

		# Get cycle count from the results file and append.
		./getFirstInteger < output-$program1.c/ta.log.000 >> results.txt
		printf " " >> results.txt
		./getFirstInteger < output-$program2.c/ta.log.000 >> results.txt
	done < $filename

else
	echo "Run with input: <permutation-file> <program-name-1> <program-name-2>"
	exit 1
fi
