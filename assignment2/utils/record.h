#ifndef _RECORD_H_
#define _RECORD_H_

// This variable should be declared in main.c. The initial value should be
// 0x1F000000 + core_index * 0x100000. The boardserver script will return any
// data written here up to the first 0 encountered.
extern volatile char *record_ptr;

// Writes a character to the log output. This is not binary safe, don't write
// 0.
int putchar(int character);
int putc(int character);

// Writes a string to the log output.
int puts(const char *str);

// Writes a decimal number to the log output.
int putd(int value);

// Writes a hexadecimal number to the log output.
int putx(int value);

// Convenience, writes a line's worth of log data following the string format
// "%s: %d\n".
void log_value(const char *s, int value);

// Convenience, records the values of the performance counters.
void log_perfcount(const char *checkpoint_name);

#endif
