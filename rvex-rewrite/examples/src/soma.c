#include "rvex.h"
#define N 10

int result[N] ={9, 9, 9, 9, 9, 9, 9, 9, 9, 9};
void soma(int v[N])
{
	int i;

	for(i = 0;i < N;i++){
	    v[i] = v[i] + 1;
}

	if ((v[0] < 5) && (v[N-1] < 5)){
     		soma(v);
    	}

	for(i = 0;i < N;i++){
	    v[i] = v[i] + 1;
	}
}


int main(void) {

	int var[N],i;
	puts("soma Test Started\n");

	for(i = 0;i < N;i++){
		var[i] = 1;
	}

	soma(var);
	for(i = 0;i < N;i++){
		if (var[i] != result[i])
			{
				rvex_fail("soma Test Failed\n");
				return 1;
			}
	}
	rvex_succeed("soma Test Passed\n");
	return 0;
}

