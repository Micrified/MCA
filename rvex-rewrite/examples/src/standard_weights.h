#ifndef __STANDARD_WEIGHTS_H__
#define __STANDARD_WEIGHTS_H__

#include "defines.h"

/*****************************************************************************/
/* standard discretisation for 3x3 stencil */
/*****************************************************************************/

/* ------------------------------------------------------------------------- */
/* compute standard discretisation 3x3 stencil weights
*/
inline void standard_weights_compute(
    /* INPUT */
    double **a, /* first diagonal entry field of diffusion tensor */
    double **b, /* off-diagonal entry of diffusion tensor */
    double **c, /* second diagonal entry of diffusion tensor */
    const int nx, /* grid size in x-direction */
    const int ny, /* grid size in y-direction */
    const int bx, /* boundary size in x-direction */
    const int by, /* boundary size in y-direction */
    const double hx, /* grid spacing in x-direction */
    const double hy, /* grid spacing in y-direction */
    const double m_alpha, /**< regularisation weight */
    /* OUTPUT */
    double ***weights /* weights for 3x3 pixel stencil for each pixel */
    )
{
  /* time savers */
  const double rxx = m_alpha / ( 2. * hx * hx );
  const double ryy = m_alpha / ( 2. * hy * hy );
  const double rxy = m_alpha / ( 2. * hx * hy );

  /* neighborhood indicators */
  /* not necessary if a, b, c were computed with
   * Neumann boundary conditions
   * and fields have Dirichlet boundary condition 0
   */
  int xm, xp, ym, yp;

  /* compute weights */
  for( int i = bx; i < bx + nx; ++i)
  {
    for( int j = by; j < by + ny; ++j)
    {
      /* set neighborhood indicators */
      xp = ( i != bx + nx - 1 )? 1.: 0;
      yp = ( j != by + ny - 1 )? 1.: 0;
      xm = ( i != bx          )? 1.: 0;
      ym = ( j != by          )? 1.: 0;

      /* lower left weight, checked */
      weights[i][j][XMYM] =
	xm * ym *
	(
	 rxy * ( 0.5 ) * ( b[i-1][j] + b[i][j-1] )
	);
      /* left weight, checked */
      weights[i][j][XMY0] =
	xm *
	(
	 rxx * ( a[i-1][j] + a[i][j] )
	);
      /* upper left weight,checked */
      weights[i][j][XMYP] =
	xm * yp *
	(
	 rxy * ( -0.5 ) * ( b[i-1][j] + b[i][j+1] )
	);
      /* upper weight, checked */
      weights[i][j][X0YP] =
	yp *
	(
	 ryy * ( c[i][j+1] + c[i][j] )
	);
      /* upper right weight, checked */
      weights[i][j][XPYP] =
	xp * yp *
	(
	 rxy * ( 0.5 ) * ( b[i+1][j] + b[i][j+1] )
	);
      /* right weight, checked */
      weights[i][j][XPY0] =
	xp *
	(
	 rxx * ( a[i+1][j] + a[i][j] )
	);
      /* lower right weight, checked */
      weights[i][j][XPYM] =
	xp * ym *
	(
	 rxy * ( -0.5 ) * ( b[i+1][j] + b[i][j-1] )
	);
      /* lower weight, checked */
      weights[i][j][X0YM] =
	ym *
	(
	 ryy * ( c[i][j-1] + c[i][j] )
	);

      /* central weight, checked */
      weights[i][j][X0Y0] =
	- (
	    weights[i][j][XMYM] +
	    weights[i][j][XMY0] +
	    weights[i][j][XMYP] +
	    weights[i][j][X0YP] +
	    weights[i][j][XPYP] +
	    weights[i][j][XPY0] +
	    weights[i][j][XPYM] +
	    weights[i][j][X0YM]
	  );

    } /* end for j */
  } /* end for i */
  /* return */
  return;
} /* end standard_weights */

/*------------------------------------------------------------------------- */

#endif
