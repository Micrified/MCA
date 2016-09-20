#ifndef __IMIO_H_
#define __IMIO_H_

/*--------------------------------------------------------------------------*/
/** \file imio.h

  \brief Input and output methods for 2D double images.

Maintainer: Stephan Didas <didas@mia.uni-saarland.de>                    */
/*--------------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>

#include "lmip_error.h"
#include "immem.h"

/*--------------------------------------------------------------------------*/

/** \brief Reads a 2D grey value image from a file in raw PGM format.

  Basically follows the specification in the Netpbm package
http://netpbm.sourceforge.net, but does only implement a limited range 
of this specification.
*/
void image_read_pgm(
    const char *file_name,   /**< name of file to read                    */
    double ***image, /**< the pointer to the image is stored here         */
    int   *nx,      /**< image size in x direction as given in the input 
		      file                                            */
    int   *ny,      /**< image size in y direction as given in the input 
		      file                                            */
    int   bx,       /**< boundary size in x direction                    */
    int   by)       /**< boundary size in y direction                    */
{
  FILE* in_file;
  char  row[256];
  int   maxval;

  /* open input file */
  in_file = fopen(file_name, "r");
  puts("opened file\n");
  if(in_file == 0)
  {
    lmip_error("Cannot open input file %s.", file_name);
  }

  /* check file type with magic number */
  if(!fgets(row, 255, in_file))
  {
    /* exit the program if the stream can't be read */
    lmip_error("Cannot read from input file %s.", file_name);
  }
  if(strncmp(row, "P5", 2))
  {
    lmip_error( "File format is not raw PGM.");
  }

  /* read comments */
  if(!fgets(row, 255, in_file))
  {
    /* exit the program if the stream can't be read */
    lmip_error("Cannot read from input file %s.", file_name);
  }
  while(row[0] == '#')
  {
    if(!fgets(row, 255, in_file))
    {
      /* exit the program if the stream can't be read */
      lmip_error("Cannot read from input file %s.", file_name);
    }

  }

  /* read width (nx) and height (ny) */
  sscanf(row, "%d %d", nx, ny);

  /* read maximal grey value */
  if(!fgets(row, 255, in_file))
  {
    /* exit the program if the stream can't be read */
    lmip_error("Cannot read from input file %s.", file_name);
  }
  sscanf(row, "%d", &maxval);

  /* allocate memory for the image */
  image_alloc(image, *nx, *ny, bx, by);

  /* read image data */
  if(maxval < 256) {
    /* one byte per pixel */
    for( int j=by; j<*ny+by; j++)
    {
      for( int i=bx; i<*nx+bx; i++)
      {
	(*image)[i][j] = (double) getc(in_file);
      }
    }
  } else {
    /* two bytes per pixel, most significant byte first */
    for( int j=by; j<*ny+by; j++)
    {
      for( int i=bx; i<*nx+bx; i++)
      {
	(*image)[i][j] = (double) getc(in_file) * 256
	  + (double) getc(in_file);
      }
    }
  }

  fclose(in_file);

  return;
} /* image_read_pgm */

/*--------------------------------------------------------------------------*/


/** \brief Writes a 2D grey value image to a file in raw PGM format.

  Basically follows the specification in the Netpbm package
http://netpbm.sourceforge.net, but does only implement a limited range 
of this specification.

This method only supports a maximal grey value of 255 so far.
The grey values are truncated to 0 and 255.
*/
void image_write_pgm(
    const char *file_name,     /**< name of file to write        */
    double **image,            /**< image data                   */
    int   nx,                 /**< image size in x direction    */
    int   ny,                 /**< image size in y direction    */
    int   bx,                 /**< boundary size in x direction */
    int   by)                 /**< boundary size in y direction */
{
  FILE* out_file;
  unsigned char byte;

  /* open output file */
  out_file = fopen(file_name, "w");
  if(out_file == 0)
  {

    lmip_error( "Could not open output file %s.", file_name);
  }

  /* ---- PGM header ---- */
  fprintf(out_file, "P5\n");

  /* image size in x and y direction */
  fprintf(out_file, "%d %d\n", nx, ny);

  /* maximal grey value */
  fprintf(out_file, "%d\n", 255);

  /* write image data */
  for( int j=by; j<ny+by; j++)
  {
    for( int i=bx; i<nx+bx; i++)
    {
      if(image[i][j] < 0) 
      {
	byte = (unsigned char) 0.0;
      } 
      else if(image[i][j] > 255.0)
      {
	byte = (unsigned char) 255.0;
      } 
      else
      {
	byte = (unsigned char) image[i][j];
      }

      if(!fwrite(&byte, sizeof(unsigned char), 1, out_file))
      {
	lmip_error( "Could not write to output file %s.", file_name);
      }
    }
  }

  fclose(out_file);

  return;
} /* image_write_pgm */

/*--------------------------------------------------------------------------*/

#endif
