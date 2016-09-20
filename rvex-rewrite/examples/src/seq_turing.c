#include <stdio.h>
#include <stdlib.h>

struct ring{
        int X;
        int Y;
};
typedef struct ring TipoRing;

void inicializaMatriz(TipoRing *game, int N, int predator, int prey, TipoRing *newMatrix){
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

void zeraAux(TipoRing *newMatrix, int N){
        int i, j;
        for(i=0;i<N;i++){
                for(j=0;j<N;j++){
                        newMatrix[(i*N)+j].X = 0;
                        newMatrix[(i*N)+j].Y = 0;
                }
        }

}

void imprimeMatriz(TipoRing *game, int N){
        int i, j;
        printf("\n");
        for(i=0;i<N;i++){
                for(j=0;j<N;j++){
                        printf("%d | %d\t\t",game[(i*N)+j].X, game[(i*N)+j].Y);
                }
                printf("\n");
        }

}

void joga(TipoRing *game, int i, int j, int N, TipoRing *newMatrix){
        int Xmenor=0, Xmaior=0, Ymenor=0, Ymaior=0, X, Y;
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
    		Xmenor =  game[((N-1)*N)+j].X;
    	} else {
    		Xmenor = game[((i-1)*N)+j].X;
    	}

    	if ((i+1) > (N-1)) {
    		Xmaior = game[j].X;
    	} else {
    		Xmaior = game[((i+1)*N)+j].X;
    	}

    	popX1 = fxy +  u*(Xmenor - (2* X) + Xmaior);
    	popY1 = gxy +  v*(Ymenor - (2* Y) + Ymaior);

    	// verifica posicao final
    	if ((j-1) < 0) {
    		Ymenor =  game[(i*N)+N-1].Y;
    	} else {
    		Ymenor = game[(i*N)+j-1].Y;
    	}

    	if ((j+1) > (N-1)) {
    		Ymaior = game[i*N].Y;
    	} else {
    		Ymaior = game[(i*N)+j+1].Y;
    	}

    	popX2 = fxy +  u*(Xmenor - (2* X) + Xmaior);
    	popY2 = gxy +  v*(Ymenor - (2* Y) + Ymaior);

    	float Xfinal = (popX1 + popX2)/2;
    	float Yfinal = (popY1 + popY2)/2;

        newMatrix[(i*N)+j].X = Xfinal;
        newMatrix[(i*N)+j].Y = Yfinal;
}

int main(int argc, char **argv){

        int N = atoi(argv[1]); //input size
        int i, row, column;          
        int x = 0;
        int prey = 100;
        int predator = 100;

        TipoRing *game = malloc(sizeof(TipoRing)*N*N);
        TipoRing *aux = malloc(sizeof(TipoRing)*N*N);        

        inicializaMatriz(game,N,predator,prey, aux);

        zeraAux(aux, N);
        
       for(x=0;x< ((N*2)-1); x++){
                for(row=0;row<N;row++){
                        for(column=0;column<N;column++){
                                if(row + column == x){
                                        joga(game, row,column, N, aux);
                                }

                        }
                }
                for(row=0;row<N;row++){
                        for(column=0;column<N;column++){
                                if(row + column == x){
                                        game[(row*N)+column].X = aux[(row*N)+column].X;
                                        game[(row*N)+column].Y = aux[(row*N)+column].Y;
                                }

                        }
                }
        }                
        return 0;
}


