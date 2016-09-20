//#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "rvex.h"

volatile int *finished1 = (int*)0x80000604;
volatile int *finished2 = (int*)0x80000608;
volatile int initialized = 0;

#define MASTER 0
#define NR_THREADS 4

int main(int argc, char** argv){


        int N = 1024-2, start, end, chunk, chunkPlus, excess;

        //args: 
        //argv[1] = start; argv[2] = end; argv[3] = get_core_ID();


        //int start = atoi(argv[1]);
        //int end = atoi(argv[2]);
        //int thread_id = atoi(argv[3]);
        int n = 1024;
        int m = 1024;
        int iter_max = 10;
        int i, j;
        int iter = 0;
        
        int thread_id = CR_CID;

        const float pi  = 2.0f * asinf(1.0f);
        
        float *A = malloc(sizeof(float)*m*n);
        float *Anew = malloc(sizeof(float)*m*n);
        float *y0 = malloc(sizeof(float)*n);
        float *aux;

        if(N%NR_THREADS == 0){
                start = (N/NR_THREADS) * thread_id;
                end = start + (N/NR_THREADS);
        }else{
                excess = N%NR_THREADS;
                chunk = N/NR_THREADS;
                chunkPlus = chunk+1;
                if(thread_id < excess){
                        start = chunkPlus*thread_id;
                        end = start + chunkPlus;
                }else{
                        start = (chunk*thread_id)+excess;
                        end = start + chunk;
                }
        }


        //Only the master thread do this
        if(thread_id == MASTER){
        		printf("Starting Jacobi\n");
        		
                memset(A, 0, n * m * sizeof(float));
                for(i = 0; i < m; i++){
                        A[i]   = 0.f;
                        A[((n-1)*m)+i] = 0.f;
                        y0[i] = sinf(pi * i / (n-1));
                        A[(i*n)] = y0[i];
                        A[(i*n)+m-1] = y0[i]*expf(-pi);        
                        Anew[i] = 0.f;
                        Anew[((n-1)*n)+i] = 0.f;
                        Anew[i*n] = y0[i];
                        Anew[(i*n)+m-1] = y0[i]*expf(-pi);
                }
                
   				initialized = 1;
				CR_CRR = 0x3210; //enable all contexts
        }
        
        while (!initialized) ;

		((char*)finished1)[thread_id] = 0;

        for(iter=0;iter<iter_max;iter++){
                for(j = start; j < end; j++){
                        for(i = 1; i < m-1; i++ ){
                            Anew[(j*n)+i] = 0.25f * ( A[(j*n)+i+1] + A[(j*n)+i-1]+ A[((j-1)*n)+i] + A[((j+1)*n)+i]);
                        }
                }

   					((char*)finished1)[thread_id] = 1;
					while (*finished1 != 0x01010101) ;
				
				initialized = 0;

                if(thread_id == MASTER){
                        aux = A;
                        A = Anew;
                        Anew = aux;
                        initialized = 1;
                }
                
                while (!initialized) ;

        }

        if(thread_id == MASTER){
                for(i=0;i<n;i++){
                        for(j=0;j<n;j++){
                                printf("%f ", A[(i*n)+j]);
                        }
                        printf("\n");
                }
        }

        return 0;
}

/* Insert this code inside of the demodispatch

if(program = 'j'){ //program = jacobi
        int N = 1024-2, start, end, chunk, chunkPlus, excess;
        if(N%NR_THREADS == 0){
                start = (N/NR_THREADS) * get_core_ID();
                end = start + (N/NR_THREADS);
        }else{
                excess = N%NR_THREADS;
                chunk = N/NR_THREADS;
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
        //argv[1] = start; argv[2] = end; argv[3] = get_core_ID();
    }
    */
