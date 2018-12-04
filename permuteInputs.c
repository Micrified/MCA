#include <stdio.h>
#include <stdlib.h>

/*
 *******************************************************************************
 *                              Global Variables                               *
 *******************************************************************************
*/


// Format: {<min>, <increment>, <max>}
int ranges[9][3] = 
{
	{2, 2, 32},		// IssueWidth/.0: No. Syllables executed per cycle (min 2).
	{2, 2, 8},		// MemLoad: No. 32-bit connections to data cache.
	{2, 2, 8}, 		// MemStore: No. 32-bit connections to data cache.
	{2, 2, 8}, 		// MemPft: No. 32-bit connections to data cache.
	{2, 2, 8},		// Alu: Number of ALU syllables executed per cycle.
	{2, 2, 8},		// Mpy: Number of multiply syllables executed per cycle.
	{2, 2, 8},		// Memory: Number of memory syllables executed per cucle.
	{32, 32, 256},	// R0: Number of 32-bit general purpose registers.
	{2, 4, 32}		// B0: Number of single-bit connection registers.
};


/*
 *******************************************************************************
 *                            Function Definitions                             *
 *******************************************************************************
*/

int main (void) {
	for (int i = ranges[0][0]; i < ranges[0][2]; i += ranges[0][1])
	for (int j = ranges[1][0]; j < ranges[1][2]; j += ranges[1][1])
	for (int k = ranges[2][0]; k < ranges[2][2]; k += ranges[2][1])
	for (int l = ranges[3][0]; l < ranges[3][2]; l += ranges[3][1])
	for (int m = ranges[4][0]; m < ranges[4][2]; m += ranges[4][1])
	for (int n = ranges[5][0]; n < ranges[5][2]; n += ranges[5][1])
	for (int p = ranges[6][0]; p < ranges[6][2]; p += ranges[6][1])
	for (int q = ranges[7][0]; q < ranges[7][2]; q += ranges[7][1])
	for (int r = ranges[8][0]; r < ranges[8][2]; r += ranges[8][1])
	fprintf(stdout, "%d %d %d %d %d %d %d %d %d\n", i, j, k, l, m, 
		n, p, q, r);

	return EXIT_SUCCESS;
}