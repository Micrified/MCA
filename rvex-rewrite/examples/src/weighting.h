#ifndef __WEIGHTING_H__
#define __WEIGHTING_H__

#include "defines.h"

/*****************************************************************************/
/* convenience method for applying the 3x3 neighborhood weights
 * to a given signal and evaluating the resulting sum
 */
/*****************************************************************************/

/*---------------------------------------------------------------------------*/

/* weight neighbors with provided weights */
inline double weighting_apply(
    /* INPUT */
    const double **u, /**< signal to be used */
    const double *weights, /**< weights array */
    const int i, /**< x-coordinate of centre */
    const int j /**< y-coordinate of centre */
    /* OUTPUT */
    /* return value */
    )
{
  /* result variable */
  double result = 0;

  /* sum up weighted neighbors */
  result =
    weights[XMYM] * u[i-1][j-1] +
    weights[XMY0] * u[i-1][j  ] +
    weights[XMYP] * u[i-1][j+1] +
    weights[X0YP] * u[i  ][j+1] +
    weights[XPYP] * u[i+1][j+1] +
    weights[XPY0] * u[i+1][j  ] +
    weights[XPYM] * u[i+1][j-1] +
    weights[X0YM] * u[i  ][j-1] ;

  /* return result */
  return result;
} /* weighting_apply */

#endif

