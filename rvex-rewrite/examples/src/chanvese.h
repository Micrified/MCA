#include <math.h>
#include "memory.h"
#include "weighting.h"
#include "standard_weights.h"
#include "immem.h"
#include "defines.h"

/* ------------------------------------------------------------------------- */

/* compute regularised L1, i.e. "differentiable absolute value" */
double regularisedL1(
    double x,
    double y,
    double eps
    ) {
  return sqrt( pow(x, 2) + pow(y, 2) + eps);
}
/*---------------------------------------------------------------------------*/

/** compute C^inf regularised Heaviside */
double regularisedH(
    double z,
    double eps
    ) {
  return 0.5 * ( 1. + 2. / M_PI * atan( z / eps ) );
}

/*---------------------------------------------------------------------------*/

/** compute regularized dirac function */
double regularisedDelta(
    double z,
    double eps
    ) {
  return 1 / (M_PI * eps)  * 1. / ( 1. + pow(z / eps, 2));
}

/*---------------------------------------------------------------------------*/

/* compute c1 and c2 */
void computeRegionAverages(
    /* INPUT */
    double **f, /** image data */
    double **phi, /** indicator function for contour */
    int nx, /** grid size in x direction */
    int ny, /** grid size in y direction */
    int bx, /** boundary size in x direction */
    int by, /** boundary size in y direction */
    double eps, /** epsilon for regularized Heaviside */
    /* OUTPUT */
    double *c1, /** average gray value in first region */
    double *c2 /** average gray value in second region */
    ) {

  /* sizes of the two regions */
  double sizeA1 = 0;
  double sizeA2 = 0;

  /* sum of gray values in each region */
  double sumA1 = 0;
  double sumA2 = 0;

  for( int i = bx; i < nx + bx; ++i) {
    for( int j = by; j < ny + by; ++j) {
      /* Heaviside */
      double H = regularisedH( phi[i][j], eps);

      /* sum up gray values und region points */
      sizeA1 += H;
      sizeA2 += 1 - H;

      sumA1 += H * f[i][j];
      sumA2 += ( 1 - H ) * f[i][j];
    }
  }

  /* compute average gray values */
  *c1 = sumA1 / sizeA1;
  *c2 = sumA2 / sizeA2;

  /* return */
  return;
}

/*---------------------------------------------------------------------------*/

/* compute diffusion tensors for Chan Vese */
void computeD (
    /* INPUT */
    double** phi, /* indicator function for curve ( has to be mirrored ) */
    int nx, /** grid size in x-direction */
    int ny, /** grid size in y-direction */
    int bx, /* boundary size in x-direction */
    int by, /** boundary size in y-direction */
    double h, /** grid spacing */
    /* OUTPUT */
    double **a, /** first diagonal entry of diffusion tensors */
    double **b, /** off-diagonal entry of diffusion tensors */
    double **c /** second diagonal entry of diffusion tensors */
    ) {

  for( int i = bx; i < nx + bx; ++i) {
    for( int j = by; j < ny + by; ++j) {
      /* x-derivative */
      const double phi_x = 1. / h * ( phi[i+1][j] - phi[i][j] );

      /* y-derivative */
      const double phi_y = 1. / h * ( phi[i][j+1] - phi[i][j] );

      /* compute derivative of regularised L1 norm */
      const double value = 1. / regularisedL1(phi_x, phi_y, 0.0001); 

      /* set diffusion tensor entries */
      a[i][j] = value;
      b[i][j] = 0;
      c[i][j] = value;
    } /* end for j */
  } /* end for i */
} /* end computeD */

/*---------------------------------------------------------------------------*/

/* perform chan-vese segmentation */
void performSegmentation(
    /* INPUT */
    double** img, /** image data */
    int nx, /** grid size in x-direction */
    int ny, /** grid size in y-direction */
    int bx, /** boundary size in x-direction */
    int by, /** boundary size in y-direction */
    double h, /** grid spacing */
    double t, /** time step size */
    double mu, /** weight penalizing curve length */
    double eta, /** weight penalizing region size */
    double lambda1, /** weight penalizing variance in first region */
    double lambda2, /** weight penalizing variance in second region */
    int laggedIter, /** iteration amount for lagged nonlinearity */
    int systemIter, /** iteration amount for linear system */
    double omega, /** relaxation parameter omega */
    /* INPUT / OUTPUT */
    double** phi /* indicator function for curve */
    ) {

  /* for copy of old values of phi */
  double **phiOld = 0;
  matrix_alloc(&phiOld, nx + 2 * bx, ny + 2 * by);

  /* storage for diffusion tensor entries */
  double **a = 0;
  double **b = 0;
  double **c = 0;

  matrix_alloc(&a, nx + 2 * bx, ny + 2 * by);
  matrix_alloc(&b, nx + 2 * bx, ny + 2 * by);
  matrix_alloc(&c, nx + 2 * bx, ny + 2 * by);


  /* storage for differential weights */
  double ***weights = 0;
  array3_alloc(&weights, nx + 2 * bx, ny + 2 * by, 9);

  /* start fixed-point iteration, use lagged-nonlinearity */
  for(int n = 0; n < laggedIter; ++n ) {

    /* make copy of old values */
    for( int i = bx; i < nx + bx; ++i) {
      for( int j = by; j < ny + by; ++j) {
	phiOld[i][j] = phi[i][j];
      }
    }

    /* enforce Neumann boundary conditions */
    image_mirror_bd(phiOld, nx, ny, bx, by);

    /* compute average gray values in current regions */
    double c1 = 0;
    double c2 = 0;
    computeRegionAverages(img, phiOld, nx, ny, bx, by, h, &c1, &c2);

    /* output values */
    printf("%lf\n", c1);
    printf("%lf\n", c2);

    /* compute diffusion tensors by using data from previous evaluation */
    computeD ( phiOld, nx, ny, bx, by, h, a, b, c);

    /* compute weights */
    standard_weights_compute(a, b, c, nx, ny, bx, by, h, h, mu, weights);

    /* difference to previous values */
    double gradient = 0;

    /* solve current system of equations */
    for( int m = 0; m < systemIter; ++m) {
      /* iterate along x-axis */
      for( int i = bx; i < nx + bx; ++i) {
	/* iterate along y-axis */
	for( int j = by; j < ny + by; ++j) {
	  /* compute dirac delta function at current location of
	   * old curve indicator function
	   */
	  const double delta = regularisedDelta( phiOld[i][j], h); 

	  /* compute lhs */
	  double lhs = 0;

	  /* contribution from time-dependent evolution */
	  lhs += 1. / t;

	  /* contribution from curve length penalization */
	  lhs -= delta * weights[i][j][X0Y0];

	  /* compute rhs */
	  double rhs = 0;

	  /* contribution of curve length penalization */
	  rhs += weighting_apply((const double **) phi, weights[i][j], i, j);

	  /* contribution from area size penalization */
	  rhs -= eta;

	  /* contribution from penalization of variance in first region */
	  rhs -= lambda1 * pow( img[i][j] - c1, 2);

	  /* contribution from penalization of variance in second region */
	  rhs += lambda2 * pow( img[i][j] - c2, 2);

	  rhs *= delta;

	  /* contribution from time-dependent evolution */
	  rhs += phiOld[i][j] / t;

	  /* save old value for relaxation step */
	  double old = phi[i][j];

	  /* perform fixed-point step */
	  phi[i][j] = omega * rhs / lhs + ( 1 - omega ) * old;
	} /* end for j */
      } /* end for i */
    } /* end for m */


    /* compute differences */
    for( int i = bx; i < nx + bx; ++i) {
      for( int j = by; j < ny + by; ++j) {
	gradient += fabs(phi[i][j] - phiOld[i][j]);
      }
    }

    gradient /= nx * ny;

    printf("gradient: %lf\n", gradient);
  } /* end for n */

  /* free storage */
  matrix_disalloc(a);
  matrix_disalloc(b);
  matrix_disalloc(c);
  matrix_disalloc(phiOld);
  array3_disalloc(weights);

} /* end performSegmentation */


/*---------------------------------------------------------------------------*/
