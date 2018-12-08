#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define AREA_ALU(n)			((n) * 3273)
#define AREA_MULT(n)		((n) * 40614)
#define AREA_LWSW(n)		((n) * 1500)
#define AREA_GPR(n)			(((n) * 6597) / 16)
#define AREA_BR(n)			(((n) * 129) / 4)
#define AREA_CONN(n)		((n) * 1000)


// Area computation function.
double getArea (double issueWidth,
			 double memLoad,
			 double memStore,
			 double memPft,
			 double alu,
			 double mpy,
			 double memory,
			 double r0,
			 double b0)
{
	return AREA_ALU(alu)  +
		   AREA_MULT(mpy) +
		   AREA_LWSW(1)   +
		   AREA_GPR(r0)   +
		   AREA_BR(b0)	  +
		   AREA_CONN((memLoad + memStore + memPft));
}

int main (void) {

	// Edit these values only.
	int issueWidth = 4;
	int memLoad = 1;
	int memStore = 1;
	int memPft = 1;
	int alu = 4;
	int mpy = 2;
	int memory = 1;
	int r0 = 64;
	int b0 = 8;
	

	// This will output the area.
	int area = (int)ceil(getArea(issueWidth, memLoad, memStore, memPft,
							  alu, mpy, memory, r0, b0));
	fprintf(stdout, "Value = %d\n", area);
	return EXIT_SUCCESS;
}