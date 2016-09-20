#include "rvex.h"

#define NTHREADS 4
#define ADDITIONS 9999

volatile int counter1;
volatile int counter2;
volatile int counter3;
volatile int counter4;
volatile int counter5;

//#define BYTES
//#define SCRATCH

#ifdef BYTES
#ifdef SCRATCH
volatile char *entering = (volatile char*) CR_GSCR_ADDR;
volatile char *ticket = (volatile char*) CR_GSCR2_ADDR;
#else
volatile char entering[NTHREADS];
volatile char ticket[NTHREADS];
#endif //SCRATCH
#else

volatile int entering[4][NTHREADS];
volatile int ticket[4][NTHREADS];

//volatile int entering[NTHREADS];
//volatile int *ticket = (volatile int*) CR_GSCR_ADDR;


#endif


void claim_lock(int l)
{
	int i, max;
	int thread_id = CR_CID;
	entering[l][thread_id] = 1;
	
	for (i = 0, max = 0; i < NTHREADS; i++)
	{
		if (ticket[l][i] > max) max = ticket[l][i];
	}
	ticket[l][thread_id] = max + 1;
	entering[l][thread_id] = 0;
	
	for (i = 0; i < NTHREADS; i++)
	{
		if (i != thread_id)
		{
			#pragma unroll(0)
			while (entering[l][i]) ; //whait while other threads picks a turn
			#pragma unroll(0)
			while (ticket[l][i] && ((ticket[l][thread_id] > ticket[l][i]) || (ticket[l][thread_id] == ticket[l][i] && thread_id > i))) ;			
		}
	}
}

void free_lock(int l)
{
	ticket[l][CR_CID] = 0;
}

int main()
{
	int i;
	CR_CRR = 0x3210;
	
	while (1){
	
	for (i = 0; i < ADDITIONS; i++)
	{
		counter1++;
	}
	
	if (CR_CID == 0)
	printf("ctr1 = %d\n", counter1);
	
	for (i = 0; i < ADDITIONS; i++)
	{
		claim_lock(0);
		counter2++;
		free_lock(0);

		claim_lock(1);
		counter3++;
		free_lock(1);

		claim_lock(2);
		counter4++;
		free_lock(2);
		
		claim_lock(3);
		counter5++;
		free_lock(3);
	}
	
	if (CR_CID == 0)
	printf("ctr2 = %d\n", counter2);
	
	}

}
