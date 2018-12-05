#include <stdio.h>
#include <stdlib.h>


int getFirstInteger () {
	int c, i = 0;

	// Drop non-digits.
	while ((c = getchar()) < '0' || c > '9');

	// First-digit.
	i = c - '0';

	// While digits on input.
	while ((c = getchar()) >= '0' && c <= '9') {
		i = 10 * i + (c - '0');
	}
	return i;
}


int main (void) {
	printf("%d", getFirstInteger());
	return EXIT_SUCCESS;
}