#include <stdio.h>
#include <stdlib.h>
#include "rvex.h"


//#define SMALLSET
#ifdef SMALLSET
#define N 8
#else
#define N 100  //define this according to the input size of matrix
#endif

#include "lu_par.h"

#define MASTER 0
#define NTHREADS 4
//#define MULTI_CONFIG 0x2100
#define MULTI_CONFIG 0x3210

#if NTHREADS == 2
#define BARRIERVAL(Y) (((Y) << 24) | ((Y) << 16))
#endif
#if NTHREADS == 3
#define BARRIERVAL(Y) (((Y) << 24) | ((Y) << 16) | ((Y) << 8))
#endif
#if NTHREADS == 4
#define BARRIERVAL(Y) (((Y) << 24) | ((Y) << 16) | ((Y) << 8) | (Y) )
#endif



/*
There is a problem with coherency in the cache.
When the bypass flag is enabled it doesnt show up.
Also with simple tests it seems to work correctly.
But in this program, the threads will start to wait for each other.
*/



#define RESOURCE_SHARE
//#define MASTERMERGE






/*These variable should be shared among all threads*/
//int *A; moved to lu_par.h





short int *c, *l;

volatile int *finished1 = (int*)0x80000604;
volatile int *finished2 = (int*)0x80000608;
volatile int initialized = 0;

volatile int barrier[4];
volatile int passedbarrier[4];

#define BYTES
#ifdef BYTES
volatile unsigned char entering[4][NTHREADS];
volatile unsigned char ticket[4][NTHREADS];
#else
volatile int entering[4][NTHREADS];
volatile int ticket[4][NTHREADS];
#endif

void merge(int barrierindex);

void claim_lock(int l)
{
	int i, max;
	int thread_id = CR_CID;
	entering[l][thread_id] = 1;
	
	for (i = 0, max = 0; i < NTHREADS; i++)
	{
		if (ticket[l][i] > max) max = ticket[i];
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

void waitbarrier(int i)
{

	#pragma unroll(0)
	while (barrier[i] != BARRIERVAL(1)) ;
	
	claim_lock(1);
	((char*)&passedbarrier[i])[CR_CID] = 1;
	free_lock(1);
	
	//Master thread reset barrier
	if (CR_CID == 0)
	{
		#pragma unroll(0)
		while (passedbarrier[i] != BARRIERVAL(1)) ; //wait for all threads to pass the barrier
		barrier[i] = 0;
		passedbarrier[i] = 0;
	}
	
}

void signalbarrier(int i)
{
	claim_lock(0);
	((char*)&barrier[i])[CR_CID] = 1;
	free_lock(0);
}

void sleep(int t)
{
	volatile int i;
	#pragma unroll(0)
	for (i = 0; i < t<<8; i++) ;
}
/*
void povoaMatrix(FILE *input, int *A){
	int i, j;
	for(i=0;i<N;i++){
		for(j=0;j<N;j++){
			fscanf(input, "%d", &A[(i*N)+j]);
		}
	}
}
*/

void printMatrix(int *M){
	int i, j;
	for(i=0;i<N;i++){
		for(j=0;j<N;j++){
			printf("%08d\t", M[(i*N)+j]);
		}
		printf("\n");
	}
}

void LUdecomposition(int *A, short int *vectorPosition, int idThread, int totalThreads, short int *l, short int *c){
	
		//these variables should be private to each thread
		int i, j, k, iteracoes=0, pos;
		int somatorio=0;
		

		//only master thread compute the first line
		if(idThread == MASTER){

#if defined(RESOURCE_SHARE) || defined(MASTERMERGE)
		CR_CRR = 0; //disable other contexts and claim all resources for ourselves
#endif					
			printf("Computing first line\n");
				for(i=1;i<N;i++){
						A[i*N] = A[i*N]/A[0];
				}
			barrier[1] = BARRIERVAL(1);
#if defined(RESOURCE_SHARE) || defined(MASTERMERGE)
		CR_CRR = MULTI_CONFIG;
#endif
		}

		waitbarrier(1);


		for(i=1;i<N;i++){
				//((char*)finished1)[idThread] = 0;


				//Only master thread do this
				if(idThread == MASTER){

#if defined(RESOURCE_SHARE) || defined(MASTERMERGE)
				CR_CRR = 0;
#endif
				#pragma unroll(0)

				printf("Computing somatorio %d\n", i);
				somatorio = 0.0;
				for(k=0;k<i;k++){
					somatorio += A[(i*N)+k] * A[(k*N)+i];
				}
				A[(i*N)+i] = A[(i*N)+i] - somatorio;
				barrier[2] = BARRIERVAL(1);
#if defined(RESOURCE_SHARE) || defined(MASTERMERGE)
				CR_CRR = MULTI_CONFIG;
#endif
				}
				/*
				else
				{
				printf("sleeping\n");
				sleep(10);
				}
				*/

				//all threads wait until the end of the master thread operation
				waitbarrier(2);
				
				//((char*)finished2)[idThread] = 0;
				//#pragma unroll(0)
				//while (*finished2 != 0) ;

				if(idThread < totalThreads/2){ //Upper computation
						if(vectorPosition[(i*2)] != -1){
								for(k=vectorPosition[i*2];k<vectorPosition[(i*2)+1];k++){
										somatorio=0.0;
										for(j=l[k];j<i;j++){
												somatorio += A[(i*N)+j] * A[(j*N)+k];
										}
										if(somatorio != 0.0)
												A[(i*N)+k] = A[(i*N)+k] - somatorio;
								}
						}
				}else{ //Low Computation
						if(vectorPosition[i*2] != -1){
								for(k=vectorPosition[i*2];k<vectorPosition[(i*2)+1];k++){
										somatorio = 0.0;
										for(j=c[k];j<i;j++){
												somatorio += A[(k*N)+j] * A[(j*N)+i];
										}
										if(somatorio != 0.0)
												A[(k*N)+i] = (A[(k*N)+i] - somatorio)/A[(i*N)+i];
								}
						}
				}
				signalbarrier(3);

#ifdef RESOURCE_SHARE
		merge(3);
#endif

				//all threads wait until the end of operation	
				waitbarrier(3);

#ifdef RESOURCE_SHARE
				CR_CRR = MULTI_CONFIG;
#endif
				
		}
}

void calcWorkload(short int *vectorPosition, int idThread, int totalThreads){
		//All the variables should be private to each thread
		int firstProcRow, firstProcCol, lastProcRow, lastProcCol, totalProcRowCol = totalThreads/2;
		int proc, sum, cont, j, i, cinit, cfinal, rinit, rfinal, ir;
		firstProcRow = 0;
		firstProcCol = totalThreads/2;
		lastProcRow = (totalThreads/2)-1;
		lastProcCol = totalThreads-1;

		for(i=0;i<N;i++){
				vectorPosition[(i*2)] = -1;
				vectorPosition[(i*2)+1] = -1;
		}

		if(idThread < totalThreads/2){
				for(j=1;j<N;j++){		
						proc = firstProcRow;
						sum = 0;
						cont = (N-(j+1))/totalProcRowCol;
						cinit = j+1;
						for(i=j+1; i<N;i++){
								sum++;
								if((sum == cont) && (proc != lastProcRow)){
										cfinal = i;
										if(proc == idThread){
												vectorPosition[(j*2)] = cinit;
												vectorPosition[(j*2)+1] = cfinal;
												//printf("Line %d --> %d ate %d\n", j, vectorPosition[j*2], vectorPosition[(j*2)+1]);
										}
										cinit = i+1;
										proc = proc+1;
										sum=0;
								}
						}
						if(cinit < i){
								if(idThread == proc){
										vectorPosition[j*2] = cinit;
										vectorPosition[(j*2)+1] = i-1;
										//printf("Line %d --> %d ate %d\n", j, vectorPosition[j*2], vectorPosition[(j*2)+1]);

								}
						}
				}
		}else{
				for(i=1; i<N; i++){
						proc = firstProcCol;
						sum=0;
						cont = (N-(i+1))/totalProcRowCol;
						rinit=i+1;
						for(j=i+1; j<N;j++){
								sum++;
								if((sum == cont) && (proc != lastProcCol)){
										rfinal = j;
										if(idThread == proc){
												vectorPosition[i*2] = rinit;
												vectorPosition[(i*2)+1] = rfinal;
												//printf("Column %i --> %d ate %d\n", i, vectorPosition[i*2], vectorPosition[(i*2)+1]);
										}
										ir = ir+1;
										rinit = j+1;
										proc = proc + 1;
										sum=0;
								}
						}
						if(rinit < j){
								if(idThread == proc){
										vectorPosition[i*2] = rinit;
										vectorPosition[(i*2)+1] = j-1;
										//printf("Column %d --> %d ate %d\n", i, vectorPosition[i*2], vectorPosition[(i*2)+1]);
								}
						}
				}

		}
}

void defineVectorZero(int *A, short int *c, short int *l){
		int i, j, cont;
		for(i=0;i<N;i++){
				cont = 0;
				for(j=0;(j<i)&&(A[(i*N)+j] == 0); j++){
						cont++;
				}
				l[i] = cont;
		}
		for(j=0;j<N;j++){
				for(i=0; (i<=j) && (A[(i*N)+j] == 0); i++){
						cont++;
				}
				c[j] = cont;
		}
}

int main(int argc, char **argv){


	int idThread = CR_CID;
	int totalThreads = NTHREADS;
	
	if (idThread == MASTER) CR_CRR = 0;
	
	
	/*This variable should be private to each thread*/
	short int *vectorPosition;
	claim_lock(0);
	vectorPosition = malloc(sizeof(short int)*N*2);
	free_lock(0);
	
	/*Only master thread do this*/
	if(idThread == MASTER){
	
			claim_lock(0);
			//A = malloc(sizeof(int)*N*N);
			c = malloc(sizeof(int)*N);
			l = malloc(sizeof(int)*N);
			free_lock(0);
			
			//printf("A 0x%x, c 0x%x, l 0x%x\n", A, c, l);
	
	/*
			A = (int*)0x200000;
			c = (short int*)0x300000;
			l = (short int*)0x400000;
	*/
			//FILE *input = fopen("niks", "r");
			//povoaMatrix(input, A);	
			defineVectorZero(A, l, c);
			//initialized = 1;
			//barrier = 1;
			//__asm__ volatile ("stop");
			CR_CRR = MULTI_CONFIG; //enable all contexts
	}
	
	//all threads wait until the end of the master thread operation
	//#pragma unroll(0)
	//while(barrier != 1) ;
	
	//((char*)finished1)[idThread] = 0;


	/* All threads do this --> workload calculation */
	calcWorkload(vectorPosition, idThread, totalThreads);

	
	//all threads wait here to start the LU decomposition together
	//((char*)finished1)[idThread] = 1;
	
	signalbarrier(0);
	
#ifdef RESOURCE_SHARE
	merge(0);
#endif

	waitbarrier(0);
	
#ifdef RESOURCE_SHARE
	CR_CRR = MULTI_CONFIG;
#endif

	LUdecomposition(A, vectorPosition, idThread, totalThreads, l, c);

	if (idThread == MASTER)
	{
	     //printMatrix(A); //To print a matrix, uncomment this line.
	     //printf("cycle count: %u\n", CR_CNT);
	}
	
	return 0;
}


void merge(int barrierindex)
{
	int i;
	int active_context;
	int new_config, tmp;
	int cur_config;
	int core_ID = (int)CR_CID;
	int active_threadcnt;
	int active_thread[4];

	claim_lock(0);
	
	cur_config = CR_CC;
	
	//printf("thread %d in merge(), config is %04x\n", core_ID, cur_config);
	
	
	
	if (cur_config == 0 || cur_config == 0x1111 || cur_config == 0x2222 || cur_config == 0x3333) 
	{
		free_lock(0);
		CR_CRR = 0x3210;
		return;
	}
	
/*
	puts("current config:\n");
	for (i = 0; i < 4; i++)
	{
		putc('0' + (cur_config>>(i*4)&0xf));
	}
	putc('\n');
*/

	/*
	 * At this point, there can be either 3, 2 or 1 busy thread.
	 * when 3, just merge into our neighbouring lanepair.
	 * when 2, split the work over 2 4-issue cores (note that this can screw up your cache locality).
	 */
	 
	 active_threadcnt = 0;
	 for (i = 0; i < NTHREADS; i++)
	 	if (((unsigned char*)&barrier[barrierindex])[i] != 1)
	 	{
	 		active_thread[active_threadcnt] = i; 
	 		active_threadcnt++;
	 	}
	 
	 //printf("barrier %08x, barrierval %d, active_threadcnt %d\n",barrier, barrierval, active_threadcnt);
	 
	 if (active_threadcnt == 3)
	 {
	 	switch (core_ID) //we know all the others are still active, choose the config that keeps cache locality
	 	{
	 		case 0:
	 			new_config = 0x3211; break;
	 		case 1:
	 			new_config = 0x3200; break;
	 		case 2:
	 			new_config = 0x3310; break;
	 		default:
	 			new_config = 0x2210; break;
	 	}
	}
	else if (active_threadcnt == 2) //we don't know which others are active, get the ones from the active_thread array
	{
		new_config = ( (active_thread[1]<<12) | (active_thread[1]<<8) | (active_thread[0]<<4) | (active_thread[0]));
	}
	else if (active_threadcnt == 1)
	{
		new_config = ( (active_thread[0]<<12) | (active_thread[0]<<8) | (active_thread[0]<<4) | (active_thread[0]));
	}
	else return; //must be 0, everyone has finished
	
/*
	puts("new config:\n");
	for (i = 0; i < 4; i++)
	{
		putc('0' + (new_config>>(i*4)&0xf));
	}
	putc('\n');
*/

	free_lock(0);

	CR_CRR = new_config;
	
	//__asm__("stop");
	return;
}

