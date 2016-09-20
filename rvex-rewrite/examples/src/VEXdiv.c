/*
 * VEXdiv.c
 *
 *  Created on: Jun 17, 2014
 *      Author: jhoozemans
 */


int VEXmoduw(unsigned long n,  unsigned long base)
{
	return ((unsigned long) n % (unsigned) base);
}

int VEXdivuw(unsigned long n,  unsigned long base)
{
	return ((unsigned long) n) / (unsigned) base;
}

int __divuw(unsigned long n,  unsigned long base)
{
	return ((unsigned long) n) / (unsigned) base;
}

int __divw(long n,  long base)
{
	return ((long) n) / base;
}

int __moduw(unsigned long n,  unsigned long base)
{
	return ((unsigned long) n % (unsigned) base);
}

int __modw(long n, long base)
{
	return ((long) n % base);
}

