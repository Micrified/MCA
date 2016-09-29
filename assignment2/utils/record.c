
#include "record.h"
#include "rvex.h"

// This variable is declared in main.c. The initial value should be
// 0x1F000000 + core_index * 0x100000. The boardserver script will return any
// data written here up to the first 0 encountered.
extern volatile char *record_ptr;

// This is the UART data register. For the UART to work properly in hardware
// you need to wait for the FIFO buffer to be ready, but the simulation doesn't
// care, and the hardware UART output is not used.
#define UART (*((volatile unsigned char *)(0xD1000000)))

int putchar(int character) {
    *record_ptr++ = character;
    UART = character;
    *record_ptr = 0;
    return 0;
}

int putc(int character) {
    *record_ptr++ = character;
    UART = character;
    *record_ptr = 0;
    return 0;
}

int puts(const char *str) {
    while (*str) {
        *record_ptr++ = *str;
        UART = *str++;
    }
    *record_ptr = 0;
    return 0;
}

int putd(int value) {
    unsigned int val;
    int i;
    char c;
    static const int decades[10] = {
        1000000000,
        100000000,
        10000000,
        1000000,
        100000,
        10000,
        1000,
        100,
        10,
        1
    };
    
    // Handle negative numbers.
    if (value < 0) {
        *record_ptr++ = '-';
        UART = '-';
        value = -value;
    }
    val = (unsigned int)value;
    
    // Divisions are really slow, so let's do without.
    c = '0';
    for (i = 0; i < 10; i++) {
        int dec = decades[i];
        if (val >= dec) {
            break;
        }
    }
    if (i == 10) {
        *record_ptr++ = '0';
        UART = '0';
    } else {
        for (; i < 10; i++) {
            int dec = decades[i];
            c = '0';
            if (val >= (dec<<3)) { val -= (dec<<3); c += 8; }
            if (val >= (dec<<2)) { val -= (dec<<2); c += 4; }
            if (val >= (dec<<1)) { val -= (dec<<1); c += 2; }
            if (val >= (dec<<0)) { val -= (dec<<0); c += 1; }
            *record_ptr++ = c;
            UART = c;
        }
    }
    *record_ptr = 0;
    return 0;
}

int putx(int value) {
    unsigned int val = (unsigned int)value;
    int i;
    char c;
    
    *record_ptr++ = '0';
    UART = '0';
    *record_ptr++ = 'x';
    UART = 'x';
    for (i = 0; i < 8; i++) {
        c = (char)(val >> 28);
        c = (c < 10) ? ('0' + c) : ('A' + c - 10);
        *record_ptr++ = c;
        UART = c;
        val <<= 4;
    }
    *record_ptr = 0;
    return 0;
}

int rvex_succeed(const char *str) {
    puts(str);
    return 0;
}

int rvex_fail(const char *str) {
    puts(str);
    return 0;
}

void log_value(const char *s, int value) {
    while (*s) {
        *record_ptr++ = *s;
        UART = *s++;
    }
    *record_ptr++ = ':';
    UART = ':';
    *record_ptr++ = ' ';
    UART = ' ';
    putd(value);
    *record_ptr++ = '\n';
    UART = '\n';
    *record_ptr = 0;
}

void log_perfcount(const char *checkpoint_name) {
    
    // Read the performance counters. The CR_* are volatile, and there should
    // be enough registers to not have to spill immediately, so this should
    // read all the registers in rapid succession.
    int cyc    = CR_CYC;
    int stall  = CR_STALL;
    int bun    = CR_BUN;
    int syl    = CR_SYL;
    int nop    = CR_NOP;
    int iacc   = CR_IACC;
    int imiss  = CR_IMISS;
    int dracc  = CR_DRACC;
    int drmiss = CR_DRMISS;
    int dwacc  = CR_DWACC;
    int dwmiss = CR_DWMISS;
    
    // Record the name of the checkpoint.
    puts(checkpoint_name);
    *record_ptr++ = '\n';
    UART = '\n';
    *record_ptr = 0;
    
    // Record the counter values.
    log_value("CYC",    cyc);
    log_value("STALL",  stall);
    log_value("BUN",    bun);
    log_value("SYL",    syl);
    log_value("NOP",    nop);
    log_value("IACC",   iacc);
    log_value("IMISS",  imiss);
    log_value("DRACC",  dracc);
    log_value("DRMISS", drmiss);
    log_value("DWACC",  dwacc);
    log_value("DWMISS", dwmiss);
    
    // Empty line at the end to separate the checkpoints nicely.
    *record_ptr++ = '\n';
    UART = '\n';
    *record_ptr = 0;
    
}

