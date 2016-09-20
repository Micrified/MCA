
#define NULL (void*)0

#include "memory.h"
#include "chanvese.h"
#include "imio.h"
#include "flags.h"

/*
 * chanvese --input PG19.pbm --output dontthinkso.pbm
 */
 
int statargc = 5;
char* statargv[] = {"chanvese", "--input", "GR19.pbm", "--output", "stuff.pbm", "\0"};


int main(int argc, char* argv[]) {

	argc = statargc;
	argv = statargv;

  char* fileName = 0;
  char* outputName = 0;

  /* time step size of parabolic pde evolution */
  double t = 10;

  /* number of steps to take */
  int steps = 10;

  /* iteration number to use for SOR */
  int iter = 100;

  /* weights for penalising color variance in the two regions */
  double lambda1 = 1;
  double lambda2 = 1;

  /* weight penalising contour length */
  double mu = 50;

  /* weight penalising size of region inside contour */
  double eta = 0;

  /* prepare flags for command line */
  struct flag_list* flags = 0;
  flags_create(&flags);

  flags_add(flags, "input", STRING, 1, 1, &fileName, 0);
  flags_add(flags, "output", STRING, 1, 1, &outputName, 0);
  flags_add(flags, "stepsize", DOUBLE, 0, 1, &t, 0);
  flags_add(flags, "lambda1", DOUBLE, 0, 1, &lambda1, 0);
  flags_add(flags, "lambda2", DOUBLE, 0, 1, &lambda2, 0);
  flags_add(flags, "mu", DOUBLE, 0, 1, &mu, 0);
  flags_add(flags, "eta", DOUBLE, 0, 1, &eta, 0);
  flags_add(flags, "steps", INTEGER, 0, 1, &steps, 0);
  flags_add(flags, "iter", INTEGER, 0, 1, &iter, 0);

  flags_read(flags, argv[0], argc, argv);
  flags_destroy(flags);

  /* dimensions of image */
  int nx = 0;
  int ny = 0;

  /* boundary size of image */
  int bx = 2;
  int by = 2;

  /* read input image */
  double** image = NULL;
  image_read_pgm(fileName, &image, &nx, &ny, bx, by);
  
  puts("image reading completed\n");

  /* allocate storage for contour */
  double** phi = 0;
  image_alloc(&phi, nx, ny, bx, by);

  /* create circle as initial contour
   * note: contour is represented as level set of a
   * two-dimensional function
   */
  for( int i = bx; i < nx + bx; ++i) {
    for( int j = bx; j < ny + by; ++j) {
      double center_x = nx / 2.;
      double center_y = ny / 2.;

      phi[i][j] = sqrt( pow(i-bx-center_x, 2) 
	  + pow(j-by-center_y, 2)) / 15. - 1;
      phi[i][j] *= -1;

    }
  }

  /* perform segmentation */
  double h = 1;
  performSegmentation(image, nx, ny, bx, by, h, t, mu, eta, lambda1, lambda2, steps, iter, 1.97, phi);

  /* create a visualization of the segmentation */
  double** seg = 0;
  image_alloc(&seg, nx, ny, bx, by);
  for(int i = bx; i < nx + bx; ++i) {
    for( int j = by; j < ny + by; ++j) {
      /* color background black and foreground white */
      seg[i][j] = ( phi[i][j] < 0)? 0: 255;
    } /* end for j */
  } /* end for i */

  /* output segmentation */
  image_write_pgm(outputName, seg, nx, ny, bx, by);

  /* free storage */
  image_disalloc(phi);
  image_disalloc(seg);
  image_disalloc(image);

  return 0;

}


typedef int int32;
typedef long long int int64;
int32 _flip_32h_smul_32_16(int32 a, int32 b)  // __st220mulhhs()
{ 
  int64 t0 = a;
  int64 t1 = b;
  int64 t2 = ( t0 * ( t1 >> 16 ) ) >> 16;
  return t2;
}

