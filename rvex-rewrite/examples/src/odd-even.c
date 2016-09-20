#include <stdio.h>
#include <stdlib.h>

//#define N 150000
#define N 20 //only to test

void sortOddEven(int *vector){
		int i, k;
		int aux;
			for(k=0;k<N/2;k++){
					for(i=0;i<N-1;i=i+2){
							if(vector[i] > vector[i+1]){
									aux = vector[i];
									vector[i] = vector[i+1];
									vector[i+1] = aux;
							}
					}
					for(i=1;i<N-1;i=i+2){
							if(vector[i] > vector[i+1]){
									aux = vector[i];
									vector[i] = vector[i+1];
									vector[i+1] = aux;
							}

					}
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
				printf("%d ", vector[i]);
		}
		printf("\n");
}

int main(int argc, char **argv){
		printf("Odd-Even starting...\n");
				
		int i, *vector;
		printf("calling malloc with size %d\n",sizeof(int)*N); 
//		vector = (int*)malloc(sizeof(int)*N);
		vector = (int*)0x400000;
		readInput(vector);
		sortOddEven(vector);

		print_vector(vector);
		
		return 0;

}
