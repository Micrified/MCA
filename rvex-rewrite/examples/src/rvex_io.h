/*****************************************************************************/
/* Platform-specific methods                                                 */
/*****************************************************************************/
// The methods below should be defined in a platform specific source.

/**
 * Prints a character to whatever platform the program is compiled for, if the
 * platform supports an output stream. Prototype conforms to the <stdio.h>
 * method.
 */
int putchar(int character);

/**
 * Same as putchar, but prints a null-terminated string. Prototype conforms to
 * the <stdio.h> method.
 */
int puts(const char *str);

/**
 * Prints the string presented to it to the standard output of the platform,
 * and in addition reports success or failure, if supported by the platform.
 */
int rvex_succeed(const char *str);
int rvex_fail(const char *str);

/**
 * Reads a character from whatever input stream the platform has available,
 * waiting until one is available. Prototype conforms to the <stdio.h> method.
 */
int getchar(void);
