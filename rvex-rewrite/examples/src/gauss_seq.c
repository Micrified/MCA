#include <stdio.h>
#include <stdlib.h>

#define maxIter 2

int N;

double *dx;
double *b;
double *A;
double *x;

void print_results()
{
	int i;
	for (i = 0; i < N; i++)
	{
		printf("%f\n", x[i]);
	}
	printf("\n");
}

int main(int argc, char **argv){
//		int N = atoi(argv[1]);
//		int maxIter = atoi(argv[2]);

		N = 64;
		
		dx = malloc(sizeof(double)*N);
		b = malloc(sizeof(double)*N);
		A = malloc(sizeof(double)*N*N);
		x = malloc(sizeof(double)*N);
		int i, j, k;
		
		printf("Starting Gauss N = %d, maxIter = %d\n", N, maxIter);

		for(i=0;i<N;i++){
				x[i] = 0;
				b[i] = 2*N;
				for(j=0;j<N;j++){
						A[(i*N)+j] = 1;
				}
				A[(i*N)+i] = N+1;
		}

		for(k=0;k<maxIter;k++){
				for(i=0;i<N;i++){
						dx[i] = b[i];
						for(j=0;j<N;j++){
								dx[i] -= A[(i*N)+j]*x[j];
						}
						dx[i] /= A[(i*N)+i];
						x[i] += dx[i];
				}
		}
		printf("Finished\n");
		print_results();
		return 0;
}
