#ifndef common_h
#define common_h

#define PI 3.14159265358979323846

int abs(int x);

double fabs(double x);

void *memcpy(void *d, const void *s, unsigned long t);

int strncmp(const char *s1, const char *s2, unsigned long n);

int rand(void);

double sin(double rad);

double cos(double rad);

double tan(double rad);

double sqrt(double val);

void putc(char c);

void puts(const char *s);

void puti(int x);

void putf(double x);

void raise(int x);

#endif
