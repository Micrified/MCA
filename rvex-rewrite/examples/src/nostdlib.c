
#include "nostdlib.h"
#include "rvex.h"
#include "rvex_io.h"

/******************************************************************************/
/*                             MEMCPY AND FRIENDS                             */
/******************************************************************************/
// TODO: write the things below in assembly with proper optimizations.

void memcpy(void *dest, const void *src, unsigned int num) {
  char *cdest = (char*)dest;
  const char *csrc = (const char*)src;
  while (num--) {
    *cdest++ = *csrc++;
  }
}

void *memmove(void *dest, const void *src, unsigned int num) {
  char *cdest = (char*)dest;
  const char *csrc = (const char*)src;
  if (cdest <= csrc) {
    memcpy(dest, src, num);
  } else {
    cdest += num;
    csrc += num;
    while (num--) {
      *--cdest = *--csrc;
    }
  }
  return dest;
}

void _bcopy(const void *src, void *dest, unsigned int num) {
  memmove(dest, src, num);
}

int memcmp(const void *a, const void *b, unsigned int num) {
  const unsigned char *ca = (const unsigned char*)a;
  const unsigned char *cb = (const unsigned char*)b;
  while (num--) {
    if (*ca == *cb) {
      ca++;
      cb++;
    } else if (*ca > *cb) {
      return 1;
    } else {
      return -1;
    }
  }
  return 0;
}

void *memset(void *ptr, int value, unsigned int num) {
  unsigned char *cptr = (unsigned char*)ptr;
  while (num--) {
    *cptr = value;
  }
  return ptr;
}

void strcpy(char *dest, const char *src) {
  while (*src) {
    *dest++ = *src++;
  }
}

int strcmp(const char *a, const char *b) {
  while (*a || *b) {
    if (*a == *b) {
      a++;
      b++;
    } else if (*a > *b) {
      return 1;
    } else {
      return -1;
    }
  }
  return 0;
}

int strlen(const char *str) {
  int count = 0;
  while (*str++) {
    count++;
  }
  return count;
}


/******************************************************************************/
/*                                    MISC.                                   */
/******************************************************************************/

int min(int a, int b) {
  return (a > b) ? b : a;
}

int max(int a, int b) {
  return (a > b) ? a : b;
}

void abort(void) {
  rvex_fail("abort() called.\n");
  while (1);
}

void exit(int code) {
  if (code) {
    rvex_fail("exit() called, code nonzero.\n");
  } else {
    rvex_succeed("exit() called, success.\n");
  }
  while (1);
}
