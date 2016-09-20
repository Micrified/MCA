#include <stdio.h>
#include <stdlib.h>
#include "rvex.h"

#define NUM 64
#define maxIter 2

#define MASTER 0
#define NR_THREADS 4

volatile int initialized = 0;

volatile int *finished1 = (int*)0x80000604;
volatile int *finished2 = (int*)0x80000608;




double *dx, *b, *A, *x;

void print_results()
{
	int i;
	for (i = 0; i < NUM; i++)
	{
		printf("0x%08x\n", x[i]);
	}
	printf("\n");
}

//int main(int argc, char **argv){
int main(){
		
		int i, j, k;
		int start, end, chunk, chunkPlus, excess;

		//volatile int c = 0;
		int size = NUM;		
		int core_id = (int)CR_CID;

		
		
		if(size%NR_THREADS == 0){
			start = (size/NR_THREADS) * core_id;
			end = start + (size/NR_THREADS);
		}else{
			excess = size%NR_THREADS;
			chunk = size/NR_THREADS;
			chunkPlus = chunk+1;
			if(core_id < excess){
				start = chunkPlus*core_id;
				end = start + chunkPlus;
			}else{
				start = (chunk*core_id)+excess;
				end = start + chunk;
			}
		}

		
		//Only the master thread do this
		if(core_id == MASTER){
		
		printf("Starting Gauss_parallel; num %d, start %d, end %d\n", NUM, start, end);

		
			/* If starting from Demodispatch:
			N = atoi(argv[1]);
			start = atoi(argv[2]);
			end = atoi(argv[3]);
			*/			

			dx = malloc(sizeof(double)*NUM);
			b = malloc(sizeof(double)*NUM);
			A = malloc(sizeof(double)*NUM*NUM);
			x = malloc(sizeof(double)*NUM);

			printf("dx %p, b %p, A %p, x %p\n", dx, b, A, x);

				for(i=0;i<NUM;i++){
						x[i] = 0;
						b[i] = 2*NUM;
						for(j=0;j<NUM;j++){
								A[(i*NUM)+j] = 1;
						}
						A[(i*NUM)+i] = NUM+1;
				}
				initialized = 1;
				
				CR_CRR = 0x3210; //Start the other contexts
		}

		//all threads wait until the end of the master thread operation
		while (initialized == 0) ;
		

		for(k=0;k<maxIter;k++){
				//printf("s %d/%d, start %d, end %d\n", k, maxIter, start, end);
				((char*)finished1)[core_id] = 0;
				
				for(i=start;i<end;i++){
//				__asm__ volatile ("nop"); //H ain't that some shit
						//printf("i %d\n", i);
						dx[i] = b[i];
						for(j=0;j<NUM;j++){
								dx[i] -= A[(i*NUM)+j]*x[j];
						}
						dx[i] /= A[(i*NUM)+i];
						x[i] += dx[i]; 
//				__asm__ volatile ("nop"); //H ain't that some shit
				}

				((char*)finished1)[core_id] = 1;

				while (*finished1 != 0x01010101) ;
				//printf("Round completed\n");

		}
		
		printf("Program Finished\n");
		print_results();
		return 0;
}

/* Insert this code inside of the demodispatch

if(program = 'g'){ //program = gauss
		int size = 2048, start, end, chunk, chunkPlus, excess;
		if(size%NR_THREADS == 0){
				start = (size/NR_THREADS) * get_core_ID();
				end = start + (size/NR_THREADS);
		}else{
				excess = size%NR_THREADS;
				chunk = size/NR_THREADS;
				chunkPlus = chunk+1;
				if(get_core_ID() < excess){
						start = chunkPlus*get_core_ID();
						end = start + chunkPlus;
				}else{
						start = (chunk*get_core_ID())+excess;
						end = start + chunk;
				}
		}
		//args: 
		//argv[1] = size; argv[2] = start; argv[3] = end
	}
	*/
