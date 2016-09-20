#ifndef __MEMORY_H__
#define __MEMORY_H__

/*--------------------------------------------------------------------------*/
/** \file memory.h

   \brief Memory allocation methods.

   Maintainer: Stephan Didas <didas@mia.uni-saarland.de>                    */
/*--------------------------------------------------------------------------*/

#include <stdlib.h>
#include <stdio.h>

/*--------------------------------------------------------------------------*/

/*--------------------------------------------------------------------------*/

/** \brief Allocates storage for a matrix of size nx * ny.

    The storage for the entries of the matrix is allocated as one linear 
    memory block. 
 */
void matrix_alloc(double ***matrix, /**< pointer to the matrix */
                  int   nx,        /**< size in x direction   */
                  int   ny)        /**< size in y direction   */
{
    double *tmp;   /* time saver */
    
    /* allocate storage and initialize data to 0 */
    tmp = (double*) calloc (nx * ny, sizeof(double));
    if (tmp == NULL)
    {
        printf("matrix_alloc: not enough storage available\n");
        exit(1);
    }
    
    *matrix = (double**) malloc (nx * sizeof(double*));
    if (*matrix == NULL)
    {
        printf("alloc_matrix: not enough storage available\n");
        exit(1);
    }
    
    for ( int i=0; i<nx; i++)
    {
        (*matrix)[i] = &(tmp[ny*i]);
    }

    return;
} /* matrix_alloc */

/*--------------------------------------------------------------------------*/

/** \brief Disallocates storage of a matrix of size nx * ny.
 */
void matrix_disalloc(double **matrix) /**< the matrix */
{
    free(matrix[0]);
    free(matrix);

    return;
} /* matrix_disalloc */

/*--------------------------------------------------------------------------*/

/** \brief Allocates storage for a three-dimensional array of size 
  n1*n2*n3.

  Exits the program with value 1 if there is not enough storage 
  available.
  */
void array3_alloc(double ****array,   /**< stores the pointer to the array  */
                  int   n1,          /**< array size in direction 1        */
                  int   n2,          /**< array size in direction 2        */
                  int   n3)          /**< array size in direction 3        */
{
    double *tmp01;   /* the data storage     */
    double **tmp02;  /* first pointer array  */

    /* allocate storage and initialize data to 0 */
    tmp01 = (double*) calloc( n1 * n2 * n3, sizeof(double) );
    if(tmp01 == NULL) 
    {
        printf("array3_alloc: not enough storage available for tmp01.\n");
        exit(1);
    }

    tmp02 = (double**) malloc( n1 * n2 * sizeof(double*) );
    if(tmp02 == NULL)
    {
        printf("array3_alloc: not enough storage available for tmp02.\n");
        exit(1);
    }

    *array = (double***) malloc( n1 * sizeof(double**) );
    if(*array == NULL)
    {
        printf("array3_alloc: not enough storage available for *array.\n");
        exit(1);
    }

    for( int i=0; i<n1; i++)
    {
        for( int j=0; j<n2; j++)
        {
            tmp02[i*n2 + j] = &( tmp01[ (i*n2 + j)*n3 ] );
        }

        (*array)[i] = &( tmp02[i*n2] );
    }
    
    return;
} /* array3_alloc */

/*--------------------------------------------------------------------------*/

/** \brief Disallocates storage of a four-dimensional array.
 */
void array3_disalloc(double ***array)   /**< the array */
{
    free(array[0][0]);
    free(array[0]);
    free(array);

    return;
} /* array3_disalloc */

/*--------------------------------------------------------------------------*/
#endif
