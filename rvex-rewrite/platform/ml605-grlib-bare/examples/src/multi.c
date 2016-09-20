#include "rvex.h"
#include "platform.h"

int main(void) {
    while (1) {
        volatile int i;
        puts("Hello world?\n");
        for (i = 0; i < 100000; i++);
    }
    return 0;
}
