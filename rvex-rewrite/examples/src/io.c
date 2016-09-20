#include <ctype.h>
#include <stdarg.h>
#include "rvex.h"

//#include <fcntl.h>
# define SEEK_SET	0	/* Seek from beginning of file.  */
# define SEEK_CUR	1	/* Seek from current position.  */
# define SEEK_END	2	/* Seek from end of file.  */

#define NULL (void*)0
typedef unsigned char uint8_t;

int fd_offset, fd_size;
uint8_t *testfile;

#define LOG_BUF_LEN	0x100000

static char buf[4][1024];

/* printk's without a loglevel use this.. */
#define DEFAULT_MESSAGE_LOGLEVEL 4 /* KERN_WARNING */

/* We show everything that is MORE important than this.. */
#define MINIMUM_CONSOLE_LOGLEVEL 1 /* Minimum loglevel we let people use */
#define DEFAULT_CONSOLE_LOGLEVEL 7 /* anything MORE serious than KERN_DEBUG */

unsigned long log_size[4] = {0,0,0,0};
struct wait_queue * log_wait = NULL;
int console_loglevel = 8;/*DEFAULT_CONSOLE_LOGLEVEL;*/


__attribute__((section (".log"))) static char log_buf[4][LOG_BUF_LEN];
//static char *log_buf = (char*)0x01000000; //would like to do this in the linker, but I cannot specify the NOLOAD attribute here

//__attribute__((section (".bss"))) static char log_buf[4][LOG_BUF_LEN];
static unsigned long log_start[4] = {0,0,0,0};
static unsigned long logged_chars[4] = {0,0,0,0};


void * memset(void * s,int c,int count)
{
	char *xs = (char *) s;

	while (count--)
		*xs++ = c;

	return s;
}


void * memcpy(void * dest,const void *src,int count)
{
	char *tmp = (char *) dest, *s = (char *) src;

	while (count--)
		*tmp++ = *s++;

	return dest;
}

int strnlen(const char * s, int count)
{
	const char *sc;

	for (sc = s; count-- && *sc != '\0'; ++sc)
		/* nothing */;
	return sc - s;
}

/*
unsigned long simple_strtoul(const char *cp,char **endp,unsigned int base)
{
	unsigned long result = 0,value;

	if (!base) {
		base = 10;
		if (*cp == '0') {
			base = 8;
			cp++;
			if ((*cp == 'x') && isxdigit(cp[1])) {
				cp++;
				base = 16;
			}
		}
	}
	while (isxdigit(*cp) && (value = isdigit(*cp) ? *cp-'0' : (islower(*cp)
	    ? toupper(*cp) : *cp)-'A'+10) < base) {
		result = result*base + value;
		cp++;
	}
	if (endp)
		*endp = (char *)cp;
	return result;
}
*/

/* we use this so that we can do without the ctype library */
#define is_digit(c)	((c) >= '0' && (c) <= '9')

static int skip_atoi(const char **s)
{
	int i=0;

	while (is_digit(**s))
		i = i*10 + *((*s)++) - '0';
	return i;
}

#define ZEROPAD	1		/* pad with zero */
#define SIGN	2		/* unsigned/signed long */
#define PLUS	4		/* show plus */
#define SPACE	8		/* space if plus */
#define LEFT	16		/* left justified */
#define SPECIAL	32		/* 0x */
#define LARGE	64		/* use 'ABCDEF' instead of 'abcdef' */


#define do_div(n,base) ({ \
int __res; \
__res = ((unsigned long) n) % (unsigned) base; \
n = ((unsigned long) n) / (unsigned) base; \
__res; })

static char * number(char * str, long num, int base, int size, int precision
	,int type)
{
	char c,sign,tmp[66];
	const char *digits="0123456789abcdefghijklmnopqrstuvwxyz";
	int i;

	if (type & LARGE)
		digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	if (type & LEFT)
		type &= ~ZEROPAD;
	if (base < 2 || base > 36)
		return 0;
	c = (type & ZEROPAD) ? '0' : ' ';
	sign = 0;
	if (type & SIGN) {
		if (num < 0) {
			sign = '-';
			num = -num;
			size--;
		} else if (type & PLUS) {
			sign = '+';
			size--;
		} else if (type & SPACE) {
			sign = ' ';
			size--;
		}
	}
	if (type & SPECIAL) {
		if (base == 16)
			size -= 2;
		else if (base == 8)
			size--;
	}
	i = 0;
	if (num == 0)
		tmp[i++]='0';
	else while (num != 0)
		tmp[i++] = digits[do_div(num,base)];
	if (i > precision)
		precision = i;
	size -= precision;
	if (!(type&(ZEROPAD+LEFT)))
		while(size-->0)
			*str++ = ' ';
	if (sign)
		*str++ = sign;
	if (type & SPECIAL) {
		if (base==8)
			*str++ = '0';
		else if (base==16) {
			*str++ = '0';
			*str++ = digits[33];
		}
	}
	if (!(type & LEFT))
		while (size-- > 0)
			*str++ = c;
	while (i < precision--)
		*str++ = '0';
	while (i-- > 0)
		*str++ = tmp[i];
	while (size-- > 0)
		*str++ = ' ';
	return str;
}

int vsprintf(char *buf, const char *fmt, va_list args)
{
	int len;
	unsigned long num;
	int i, base;
	char * str;
	const char *s;

	int flags;		/* flags to number() */

	int field_width;	/* width of output field */
	int precision;		/* min. # of digits for integers; max
				   number of chars for from string */
	int qualifier;		/* 'h', 'l', or 'L' for integer fields */

	for (str=buf ; *fmt ; ++fmt) {
		if (*fmt != '%') {
			*str++ = *fmt;
			continue;
		}

		/* process flags */
		flags = 0;
		repeat:
			++fmt;		/* this also skips first '%' */
			switch (*fmt) {
				case '-': flags |= LEFT; goto repeat;
				case '+': flags |= PLUS; goto repeat;
				case ' ': flags |= SPACE; goto repeat;
				case '#': flags |= SPECIAL; goto repeat;
				case '0': flags |= ZEROPAD; goto repeat;
				}

		/* get field width */
		field_width = -1;
		if (is_digit(*fmt))
			field_width = skip_atoi(&fmt);
		else if (*fmt == '*') {
			++fmt;
			/* it's the next argument */
			field_width = va_arg(args, int);
			if (field_width < 0) {
				field_width = -field_width;
				flags |= LEFT;
			}
		}

		/* get the precision */
		precision = -1;
		if (*fmt == '.') {
			++fmt;
			if (is_digit(*fmt))
				precision = skip_atoi(&fmt);
			else if (*fmt == '*') {
				++fmt;
				/* it's the next argument */
				precision = va_arg(args, int);
			}
			if (precision < 0)
				precision = 0;
		}

		/* get the conversion qualifier */
		qualifier = -1;
		if (*fmt == 'h' || *fmt == 'l' || *fmt == 'L') {
			qualifier = *fmt;
			++fmt;
		}

		/* default base */
		base = 10;

		switch (*fmt) {
		case 'c':
			if (!(flags & LEFT))
				while (--field_width > 0)
					*str++ = ' ';
			*str++ = (unsigned char) va_arg(args, int);
			while (--field_width > 0)
				*str++ = ' ';
			continue;

		case 's':
			s = va_arg(args, char *);
			if (!s)
				s = "<NULL>";

			len = strnlen(s, precision);

			if (!(flags & LEFT))
				while (len < field_width--)
					*str++ = ' ';
			for (i = 0; i < len; ++i)
				*str++ = *s++;
			while (len < field_width--)
				*str++ = ' ';
			continue;

		case 'p':
			if (field_width == -1) {
				field_width = 2*sizeof(void *);
				flags |= ZEROPAD;
			}
			str = number(str,
				(unsigned long) va_arg(args, void *), 16,
				field_width, precision, flags);
			continue;


		case 'n':
			if (qualifier == 'l') {
				long * ip = va_arg(args, long *);
				*ip = (str - buf);
			} else {
				int * ip = va_arg(args, int *);
				*ip = (str - buf);
			}
			continue;

		/* integer number formats - set up the flags and "break" */
		case 'o':
			base = 8;
			break;

		case 'X':
			flags |= LARGE;
		case 'x':
			base = 16;
			break;

		case 'd':
		case 'i':
			flags |= SIGN;
		case 'u':
			break;

		default:
			if (*fmt != '%')
				*str++ = '%';
			if (*fmt)
				*str++ = *fmt;
			else
				--fmt;
			continue;
		}
		if (qualifier == 'l')
			num = va_arg(args, unsigned long);
		else if (qualifier == 'h')
			if (flags & SIGN)
				num = va_arg(args, int);
			else
				num = va_arg(args, unsigned);
		else if (flags & SIGN)
			num = va_arg(args, int);
		else
			num = va_arg(args, unsigned int);
		str = number(str, num, base, field_width, precision, flags);
	}
	*str = '\0';
	return str-buf;
}

int sprintf(char * buf, const char *fmt, ...)
{
	va_list args;
	int i;

	va_start(args, fmt);
	i=vsprintf(buf,fmt,args);
	va_end(args);
	return i;
}



int printf(const char *fmt, ...)
{
	va_list args;
	int i;
	char *msg, *p, *buf_end;
	long flags;

	va_start(args, fmt);
	i = vsprintf(buf[CR_CID], fmt, args); /* hopefully i < sizeof(buf)-4 */
	buf_end = buf[CR_CID] + i;
	va_end(args);
	for (p = buf[CR_CID]; p < buf_end; p++) {
		msg = p;
		for (; p < buf_end; p++) {
			log_buf[CR_CID][(log_start[CR_CID]+log_size[CR_CID]) & (LOG_BUF_LEN-1)] = *p;
			if (log_size[CR_CID] < LOG_BUF_LEN)
				log_size[CR_CID]++;
			else {
				log_start[CR_CID]++;
				log_start[CR_CID] &= LOG_BUF_LEN-1;
			}
			logged_chars[CR_CID]++;
			if (*p == '\n')
				break;
		}

		if (CR_CID == 0) puts(msg); //Lets have only thread 0 print to the UART to keep output readable. The rest will still write to their logbufs.
	}
	return i;
}


#ifdef IO_LINK_FILE
//extern int* _binary_GR19_pgm_start, _binary_GR19_pgm_end;
extern int* _binary_matrix_txt_start, _binary_matrix_txt_end;
int open(char* path, int mode)
{
	fd_offset = 0;
	fd_size = ((unsigned int)&_binary_matrix_txt_end - (unsigned int)&_binary_matrix_txt_start);
	testfile = (uint8_t*)&_binary_matrix_txt_start;
	printf("open assume opening FILENAME at address 0x%08x, size %d bytes\n", testfile, fd_size);
	return 0;
}

int close(char *fname)
{
	return 0;
}


int read(int fd, uint8_t* buf, int len)
{
	int nbytes_read = 0;
	if (fd_offset + len > fd_size) //reading more bytes than there are left in the file
	{
		len = fd_size - fd_offset;
	}
	while (nbytes_read < len)
	{
		buf[nbytes_read++] = testfile[fd_offset++];
	}
	return nbytes_read;
}

int lseek(int fd, int offset, int whence)
{
	switch (whence)
	{
	case (SEEK_SET) :
	{
		if (0 + offset > fd_size)
		{
			fd_offset = fd_size;
			return fd_offset;
		}
		else if (0 + offset < 0)
		{
			fd_offset = 0;
			return fd_offset;
		}
		else
		{
			fd_offset = offset;
			return offset;
		}
	}; break;
	case (SEEK_CUR) :
	{
		if (fd_offset + offset > fd_size)
		{
			fd_offset = fd_size;
			return fd_offset;
		}
		else if (fd_offset + offset < 0)
		{
			fd_offset = 0;
			return fd_offset;
		}
		else
		{
			fd_offset += offset;
			return offset;
		}
	}; break;
	case (SEEK_END) :
	{
		if (fd_size + offset > fd_size)
		{
			fd_offset = fd_size;
			return fd_offset;
		}
		else if (fd_size + offset < 0)
		{
			fd_offset = 0;
			return fd_offset;
		}
		else
		{
			fd_offset = fd_size + offset;
			return fd_offset;
		}
	}; break;
	default:
		return -1;
	}

}
#endif /* FILENAME */

int fprintf ( int *stream, const char * format, ... )
{
	int retval;
	va_list args;
	va_start(args, format);
	retval = printf(format, args);
	va_end(args);
	return retval;
}

void exit(int exit_code)
{
	//H Just crash
	__asm__("stop") ;
//	*(volatile unsigned int*)0x1 = 0; //should trigger an unaligned access exception
}

