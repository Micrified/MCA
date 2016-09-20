#ifndef __IMMEM_H__
#define __IMMEM_H__

/*--------------------------------------------------------------------------*/
/** \file immem.h

   \brief Memory allocation methods for 2D double images.

   Maintainer: Stephan Didas <didas@mia.uni-saarland.de>                    */
/*--------------------------------------------------------------------------*/

#include <stdlib.h>

#include "memory.h"

/*--------------------------------------------------------------------------*/

/** \brief Allocates storage for an image of size nx*ny with boundary size 
    bx and by.

    Uses matrix_alloc to allocate storage for a matrix of size
    (nx + 2*bx) * (ny + 2*by) * sizeof(double).

    Exits the program with value 1 if there is not enough storage available.
 */
void image_alloc(double ***image,  /**< the pointer to the image is 
				        stored here                  */
                 int   nx,        /**< image size in x direction    */
                 int   ny,        /**< image size in y direction    */
		 int   bx,        /**< boundary size in x direction */
		 int   by)        /**< boundary size in y direction */
{
    matrix_alloc(image, nx + 2*bx, ny + 2*by);
    
    return;
} /* image_alloc */

/*--------------------------------------------------------------------------*/

/** \brief Disallocates storage of an image. 

    Uses matrix_disalloc to free the storage.
 */
void image_disalloc(double **image)  /**< pointer to the image         */
{
    matrix_disalloc(image);

    return;
} /* image_disalloc */

/*--------------------------------------------------------------------------*/

/** \brief Copies one image into another with same boundary size.
 */
void image_copy(const double **source, /**< source image                 */
		int   nx,       /**< image size in x direction    */
		int   ny,       /**< image size in y direction    */
		int   bx,       /**< boundary size in x direction */
		int   by,       /**< boundary size in y direction */
		double **dest)   /**< destination image            */
{
    for( int i=bx; i<nx+bx; i++)
    {
	for( int j=by; j<ny+by; j++)
	{
	    dest[i][j] = source[i][j];
	}
    }

    return;
} /* image_copy */

/*--------------------------------------------------------------------------*/

/** \brief Mirrors the boundary of a 2D image.
 */
void image_mirror_bd(
    double **u,       /**< the image                    */
    int   nx,        /**< image size in x direction    */
    int   ny,        /**< image size in y direction    */
    int   bx,        /**< boundary size in x direction */
    int   by)        /**< boundary size in y direction */
{
    for( int i=bx; i<nx+bx; i++)
    {
	for( int j=0; j<by; j++)
	{
	    u[i][by-j-1 ] = u[i][by+j     ];
	    u[i][ny+by+j] = u[i][ny+by-j-1];
	}
    }

    for( int i=0; i<bx; i++)
    {
	for( int j=0; j<ny+2*by; j++)
	{
	    u[bx-i-1 ][j] = u[bx+i     ][j];
	    u[nx+bx+i][j] = u[nx+bx-i-1][j];
	}
    }

    return;
} /* image_mirror_bd */


/*--------------------------------------------------------------------------*/
#endif
