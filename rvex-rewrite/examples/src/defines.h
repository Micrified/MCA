#ifndef __DEFINES_H__
#define __DEFINES_H__

/* definition of M_PI if not present */
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef M_PI_2
#define M_PI_2 ( M_PI / 2. )
#endif

/* defines for neighborhood in 3x3 stencil */
#define XMYM 0 
#define XMY0 1
#define XMYP 2
#define X0YM 3
#define X0YP 4
#define XPYM 5
#define XPY0 6
#define XPYP 7
#define X0Y0 8

#endif
