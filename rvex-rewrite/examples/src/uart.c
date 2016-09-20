#include "rvex.h"

int main(void) {
  unsigned char c;
  puts("Hello");
  while (1) {
    c = getchar();
    if ((c >= 'a') && (c <= 'z')) {
      c += 'A' - 'a';
    }
    putchar(c);
  }
}
