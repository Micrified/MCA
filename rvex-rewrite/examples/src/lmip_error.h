#ifndef __LMIP_ERROR_H__
#define __LMIP_ERROR_H__
#ifndef LINUX
#define lmip_error printf
#else
#include <error.h>
#define lmip_error(...) error_at_line(1, 0, __FILE__, __LINE__,  __VA_ARGS__)
#endif
#endif
