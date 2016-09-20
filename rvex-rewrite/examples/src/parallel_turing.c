#include <stdio.h>
#include <stdlib.h>
#include "rvex.h"

#define NR_THREADS 4
#define MASTER 0

volatile int initialized = 0;

volatile int *finished1 = (int*)0x80000604;
volatile int *finished2 = (int*)0x80000608;

struct ring{
        int X;
        int Y;
};
typedef struct ring TypeRing;

void initializeMatrix(TypeRing *game, int N, int predator, int prey, TypeRing *newMatrix){
        int i, j;
        for(i=0;i<N;i++){
                for(j=0;j<N;j++){
                        game[(i*N)+j].X = predator;
                        game[(i*N)+j].Y = prey;
                        newMatrix[(i*N)+j].X = 0;
                        newMatrix[(i*N)+j].Y = 0;
                }
        }
}

void zeraAux(TypeRing *newMatrix, int N){
        int i, j;
        for(i=0;i<N;i++){
                for(j=0;j<N;j++){
                        newMatrix[(i*N)+j].X = 0;
                        newMatrix[(i*N)+j].Y = 0;
                }
        }

}

void printMatrix(TypeRing *game, int N){
        int i, j;
        printf("\n");
        for(i=0;i<N;i++){
                for(j=0;j<N;j++){
                        printf("%d | %d\t",game[(i*N)+j].X, game[(i*N)+j].Y);
                }
                printf("\n");
        }

}

void playGame(TypeRing *game, int i, int j, int N, TypeRing *newMatrix){
        int Xm=0, XM=0, Ym=0, YM=0, X, Y;
        float rx = 0.0798; 
        float ax = 0.0123; 
        float bx = 0.0377; 
        float u = 0.12; 
        float ry = 0.0178; 
        float ay = 0.0998; 
        float by = 0.0100; 
        float v = 0.13; 

        float popX1, popY1, popX2, popY2;
        float fxy, gxy;

        X = game[(i*N)+j].X;
        Y = game[(i*N)+j].Y;

        fxy = X*(rx + (ax * X) + (bx * Y));
        gxy = Y*(ry + (ay * X) + (by * Y));

    	// verificando  posicao anterior
    	if ((i-1) < 0) {
    		Xm =  game[((N-1)*N)+j].X;
    	} else {
    		Xm = game[((i-1)*N)+j].X;
    	}

    	if ((i+1) > (N-1)) {
    		XM = game[j].X;
    	} else {
    		XM = game[((i+1)*N)+j].X;
    	}

    	popX1 = fxy +  u*(Xm - (2* X) + XM);
    	popY1 = gxy +  v*(Ym - (2* Y) + YM);

    	// verifica posicao final
    	if ((j-1) < 0) {
    		Ym =  game[(i*N)+N-1].Y;
    	} else {
    		Ym = game[(i*N)+j-1].Y;
    	}

    	if ((j+1) > (N-1)) {
    		YM = game[i*N].Y;
    	} else {
    		YM = game[(i*N)+j+1].Y;
    	}

    	popX2 = fxy +  u*(Xm - (2* X) + XM);
    	popY2 = gxy +  v*(Ym - (2* Y) + YM);

    	float Xfinal = (popX1 + popX2)/2;
    	float Yfinal = (popY1 + popY2)/2;

        newMatrix[(i*N)+j].X = Xfinal;
        newMatrix[(i*N)+j].Y = Yfinal;
}

int main(int argc, char **argv){
/*
        int N = atoi(argv[1]);
        int start = atoi(argv[2]);
        int end = atoi(argv[3]);
*/
		int N = 64;
		int start, end, chunk, chunkPlus, excess;

        int x = 0;
        int i, row, column;
        int prey = 100;
        int predator = 100;
        
        int thread_id = CR_CID;
        
        
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

		

        TypeRing *game = malloc(sizeof(TypeRing)*N*N);
        TypeRing *aux = malloc(sizeof(TypeRing)*N*N);        


        if(thread_id == MASTER){
                initializeMatrix(game,N,predator,prey, aux);
                zeraAux(aux, N);
                initialized = 1;
                CR_CRR = 0x3210; //start other contexts
        }

		while (initialized = 0) ;
               
       for(x=0;x< ((N*2)-1); x++){
       
       			((char*)finished1)[thread_id] = 0;
                for(row=start;row<end;row++){
                        for(column=0;column<N;column++){
                                if(row + column == x){
                                        playGame(game, row,column, N, aux);
                                }

                        }
                }
                
                ((char*)finished1)[thread_id] = 1;
                while (*finished1 != 0x01010101) ;
                
                ((char*)finished2)[thread_id] = 0;
                
                for(row=start;row<end;row++){
                        for(column=0;column<N;column++){
                                if(row + column == x){
                                        game[(row*N)+column].X = aux[(row*N)+column].X;
                                        game[(row*N)+column].Y = aux[(row*N)+column].Y;
                                }

                        }
                }
                ((char*)finished2)[thread_id] = 1;
                while (*finished2 != 0x01010101) ;
					
					initialized = 0;
					if (CR_CID == MASTER)
					{
						printf("Round complete: \n");
						printMatrix(game, N);
						initialized = 1;
					}
					while (initialized == 0) ;
        }                
        return 0;
}

/* Insert the following code on the DemoDispatch 

    if(program = 't'){ //program = turing-ring
            int size = 1024, start, end, chunk, chunkPlus, excess;//input size
            if(size%NR_THREADS == 0){
                    start = (size/NR_THREADS) * thread_id;
                    end = start + (size/NR_THREADS);
            }else{
                    excess = size%NR_THREADS;
                    chunk = size/NR_THREADS;
                    chunkPlus = chunk+1;
                    if(thread_id < excess){
                            start = chunkPlus*thread_id;
                            end = start + chunkPlus;
                    }else{
                            start = (chunk*thread_id)+excess;
                            end = start + chunk;
                    }

            }
            //argv[1] = size; argv[2] = start; argv[3] = end
    }

*/
