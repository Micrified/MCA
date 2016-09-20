#include <stdio.h>
#include <stdlib.h>
#include "rvex.h"

//#define N 150000
#define N 32 //only to test
#define NR_THREADS 4

#define MASTER 0

/* Synchronization gets a little freaky within atomic instructions.
 * I'm using the dirty char* trick so that each core has its own byte to write to,
 * but still being able to read the value to check the flags.
 * This way, the cores do not need to read the value first, OR in their flag, and write the result back.
 */
//volatile int finished1[4] = {0,0,0,0};
//volatile int finished2[4] = {0,0,0,0};

/* Another problem; the cache first updates the line when performing a write to memory that is smaller than a word.
 * So the trick still doesn't work for cached memory. We'll have to abuse some non-cached memory location,
 * such as a memory-mapped control register for this.
 */
volatile int *finished1 = (int*)0x80000604;
volatile int *finished2 = (int*)0x80000608;
volatile int initialized = 0;

int vector[N];

void sortOddEven(int *vector, int iniOdd, int endOdd, int iniEven, int endEven){
		int i, k;
		int aux;
		int thread_id = CR_CID;
		
		printf("Sorting with N %d, iniOdd %d, endOdd %d, iniEven %d, endEven %d\n", N, iniOdd, endOdd, iniEven, endEven);
			for(k=0;k<(N+1)/2;k++){ //need 1 extra run for odd N
			
					//finished1[thread_id] = 0;
					((char*)finished1)[thread_id] = 0;
					for(i=iniEven;i<endEven;i=i+2){
							if(vector[i] > vector[i+1]){
									aux = vector[i];
									vector[i] = vector[i+1];
									vector[i+1] = aux;
							}
					}
					//finished1[thread_id] = (1<<thread_id); //flag that we're finished
					((char*)finished1)[thread_id] = 1;
					//while ((finished1[0] & finished1[1] & finished1[2] & finished1[3]) != 0xf) ; //wait for the rest
					while (*finished1 != 0x01010101) ;
					//finished2[thread_id] = 0;
					
					initialized = 0;
					if (CR_CID == MASTER)
					{
						printf("Round complete: \n");
						print_vector(vector);
						initialized = 1;
					}
					while (initialized == 0) ;
					
					((char*)finished2)[thread_id] = 0;
					for(i=iniOdd;i<endOdd;i=i+2){
							if(vector[i] > vector[i+1]){
									aux = vector[i];
									vector[i] = vector[i+1];
									vector[i+1] = aux;
							}

					}
					//finished2[thread_id] = (1<<thread_id); //flag that we're finished
					((char*)finished2)[thread_id] = 1;
					//while ((finished2[0] & finished2[1] & finished2[2] & finished2[3]) == 0xf) ; //wait for the rest
					while (*finished2 != 0x01010101) ;
					
					initialized = 0;
					if (CR_CID == MASTER)
					{
						printf("Round complete: \n");
						print_vector(vector);
						initialized = 1;
					}
					while (initialized == 0) ;
		}

}

void readInput(int *vector){
		int i;
		for(i=0;i<N;i++){
				vector[i] = N-i;
		}
}

void print_vector(int *vector){
		int i;
		for(i=0;i<N;i++){
				printf("%02d ", vector[i]);
		}
		printf("\n");
}

int main(int argc, char **argv){
		
		int i;
		/* When using Demodispatch
		int iniOdd = atoi(argv[1]);
		int endOdd = atoi(argv[2]);
		int iniEven = atoi(argv[3]);
		int endEven = atoi(argv[4]);
		*/
		
		int thread_id = CR_CID;
		
		
		int nChanges = N/2;
		int chunk, excess, chunkPlus, iniOdd, iniEven, endOdd, endEven;
		//Adjusting even
		if(nChanges%NR_THREADS == 0){
				iniEven = ((nChanges/NR_THREADS)*thread_id)*2;
				endEven = iniEven + ((nChanges/NR_THREADS))*2;
		}else{
				excess = nChanges%NR_THREADS;
				chunk = nChanges/NR_THREADS;
				chunkPlus = chunk+1;
				if(thread_id < excess){
						iniEven = chunkPlus*thread_id*2;
						endEven = iniEven+(chunkPlus*2);
				}else{
						iniEven = ((chunk*thread_id)+excess)*2;
						endEven = iniEven+(chunk*2);
				}
		}
		//Adjusting odd
		nChanges = (N-1)/2;

		if(nChanges == 0)
				nChanges = 1;
		if(nChanges%NR_THREADS == 0 && nChanges > 1){
				iniOdd = (((nChanges/NR_THREADS)*thread_id)*2)+1;
				endOdd = iniOdd+((nChanges/NR_THREADS)*2);
		}else{
				chunk = nChanges/NR_THREADS;
				chunkPlus = chunk+1;
				excess = nChanges%NR_THREADS;
				if(thread_id < excess){
						iniOdd = (thread_id*(chunkPlus*2))+1;
						endOdd = iniOdd + (chunkPlus*2);
				}else{
						iniOdd = (((chunk*thread_id) + excess)*2)+1;
						endOdd = iniOdd + (chunk*2);
				}
		}
	
		
		//vector = malloc(sizeof(int)*N);
		//only thread MASTER should execute the function readInput
		if(thread_id == MASTER){
			printf("Starting parallel Odd-Even sort\n");
			readInput(vector);
			print_vector(vector);
			initialized = 1;
			CR_CRR = 0x3210; //enable all contexts
		}
		//all threads wait until the end of the master thread operation
		while(initialized == 0) ;
		
		sortOddEven(vector, iniOdd, endOdd, iniEven, endEven);
		
		//only thread MASTER should execute the function print_vector();
		if(thread_id == MASTER){
			print_vector(vector);	
		}
		return 0;
}

/* #############################################
	Insert this code inside of the demodispatch
   #############################################
	if(program = 'o'){ //program = odd-even
			int N = 100;//Input size.
			int nChanges = N/2;
			int chunk, excess, chunkPlus, iniOdd, iniEven, endOdd, endEven;
			//Adjusting even
			if(nChanges%NR_THREADS == 0){
					iniEven = ((nChanges/NR_THREADS)*thread_id)*2;
					endEven = iniEven + ((nChanges/NR_THREADS))*2;
			}else{
					excess = nChanges%NR_THREADS;
					chunk = nChanges/NR_THREADS;
					chunkPlus = chunk+1;
					if(i < excess){
							iniEven = chunkPlus*thread_id*2;
							endEven = iniEven+(chunkPlus*2);
					}else{
							iniEven = ((chunk*thread_id)+excess)*2;
							endEven = iniEven+(chunk*2);
					}
			}
			//Adjusting odd
			if(N%2 == 0){
					nChanges = (N/2)-1;
			}else{
					nChanges = (N/2);
			}
			if(nChanges == 0)
					nChanges = 1;
			if(nChanges%NR_THREADS == 0 && nChanges > 1){
					iniOdd = (((nChanges/NR_THREADS)*thread_id)*2)+1;
					endOdd = iniOdd+((nChanges/NR_THREADS)*2);
			}else{
					chunk = nChanges/NR_THREADS;
					chunkPlus = chunk+1;
					excess = nChanges%NR_THREADS;
					if(i < excess){
							iniOdd = (thread_id*chunkPlus)+1;
							endOdd = iniOdd + (chunkPlus*2);
					}else{
							iniOdd = (((chunk*thread_id) + excess)*2)+1;
							endOdd = iniOdd + (chunk*2);
					}
			}
	}
		//args
		//argv[1] = iniOdd; argv[2] = endOdd; argv[3] = iniEven; argv[4] = oddEven;
	*/	
