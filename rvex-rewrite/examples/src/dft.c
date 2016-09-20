#include "rvex.h"

typedef unsigned int uint32_t;
typedef signed int int32_t;
typedef unsigned char uint8_t;
typedef signed char int8_t;


typedef int32_t fp15p17_t;
typedef uint32_t ufp27p5_t;

#define _itofp15p17(x)  ( (int32_t)  (x) << 17 )
#define itofp15p17(x)   _itofp15p17(x)
#define _mulfp15p17(x,y)  ( cast_int32( sra(mult(x, y), 17) ) )
#define _mulfp27p5(x,y)   ( cast_int32( sra(mult(x, y), 5) ) )
#define mulfp27p5(x,y)   _mulfp27p5(x,y)
#define mulfp15p17(x,y)  _mulfp15p17(x,y)

#define N 24

/* row sums for direction 0 */ 
int rowsums[N]= { 759, 776, 787, 795, 797, 796, 801, 805, 800, 800, 799, 801, 799, 790, 781, 775, 772, 769, 768, 767, 762, 761, 755, 751};

fp15p17_t dft_waves_cos[96];
fp15p17_t dft_waves_sin[96];

/* a 64 bit integer*/
typedef struct {
	uint32_t high;
	uint32_t low;
} int_64_t;


uint32_t cast_uint32(int_64_t x) 
{	
	uint32_t res;

	res = x.low;

	if (x.high != 0) {
//	    fprintf(stderr, "ERROR: incorrect unsigned cast:%08x.%08x \n", x.high, x.low);
        }

	return res;
}

/* expects to receive a 64-bit signed integer*/
int32_t cast_int32(int_64_t x) 
{
	
    int32_t result = 0; 
 
    /* check sign of "long long int type"*/
    if(x.high & 0x80000000L) { /*negative 64-bit intger*/

       if(x.high == 0xFFFFFFFFL) {
	  /* high contains only sign extended bits from negative low word*/
          result = (int32_t)x.low; 
       }
       else {/* high contains other bits than extended sign bits of low word*/
//	  fprintf(stderr, "ERROR : incorrect negative cast:%8x.%08x \n", x.high, x.low);
       } 
    }
    else {/* narrow casting positive or zero 64-bit signed integer*/ 

	if(x.high == 0x00000000L) {
	  /* no information lost*/
          result = (int32_t)x.low; 
	}
	else{
	  /* high contains only sign extended bits from positive low word*/
//	  fprintf(stderr, "ERROR : incorrect positive cast:%08x.%08x \n", x.high, x.low);	
	}
    }

    return result;     
}


int_64_t cast(int32_t x)
{
	int_64_t llong;
	
	/*copy x to low word*/
	llong.low = x;
	
	/* sign extent when x is negative */
	if(x < 0) {
		llong.high = 0xFFFFFFFFL; /* -1*/
	}
	else {
		llong.high = 0;
	}
	
	return llong;
}
/* Vex doesn't have long long ints, so we need to determine if the
   low halves of our 64-bit integers will generate a carry when added */ 
int_64_t add(int_64_t x, int_64_t y) 
{
	
	unsigned long int x1, x2, y1, y2, z1, z2;
	int_64_t sum;
	
	/* intialize x1, x2, y1, y2 */
	x1 = x.low; x2 = x.high;
	y1 = y.low; y2 = y.high;
	
	z1 = z2 = 0;
	
	z1 = x1 + y1;
	if(z1 < x1 || z1 < y1)
	{ /* when sum is smaller than either terms carry was generated*/
		z2++;
	}
	z2 += x2 + y2;
	
	sum.low = z1;
	sum.high = z2;
	
	return sum;
}


int_64_t neg(int_64_t x) 
{	
	x.low = ~x.low;
	x.high = ~x.high;

	return add(x, cast(1));
}


int abs(int x)  
{
        if (x < 0) {
                return -x;
	}
        else {
            	return x;
	}
}


int_64_t ucast(uint32_t x) 
{
	int_64_t llong;
	
	/*copy x to low word*/
	llong.low = x;
	llong.high = 0;
	
	return llong;
}

/*logical shifts of 64-bit intger type*/
int_64_t sll(int_64_t value, unsigned char pos) 
{

	unsigned long int temp = 0;/*long int*/
	
	if (pos < 32) {
		/*shift high word left pos bits*/
		value.high <<= pos;
		/* shift low (32 - pos) bits right*/
		temp = value.low >> (32 - pos);
		/* add temp to high word */ 
		value.high |= temp;
		/* shift low word*/
		value.low <<= pos;	
	}
	else{
		value.high = value.low << (pos - 32);
		value.low = 0;
	}
	
	return value;
}


int_64_t sra(int_64_t value, unsigned char pos) 
{
        unsigned int temp = 0;

        if (pos < 32) {
                value.low >>= pos;
                temp = value.high << (32 - pos);
                value.low |= temp;
                /*copy sign bits to the right */
                value.high = ((int32_t)value.high) >> pos;  /* cast to int32_t to force compiler to use arithmetic shift */
        }
        else {
                value.low = ((int32_t)value.high) >> (pos - 32); /*brackets added for certainty of issuing artimitic shift*/
                value.high = 0xFFFFFFFFL;/* -1 */
        }

        return value;
}


int_64_t umult(register unsigned long a, register unsigned long b) 
{
 
	unsigned long a_low = a & 0xffff;
	unsigned long a_high = a >> 16;
	unsigned long b_low = b & 0xffff;
	unsigned long b_high = b >> 16;
	
	unsigned long p_ll = a_low * b_low;
	unsigned long p_lh = a_low * b_high;
	unsigned long p_hl = a_high * b_low;
	unsigned long p_hh = a_high * b_high;
		
        /* accumulate results to take care of intermediate carries */
	int_64_t res = ucast(p_ll);  
	res = add(res, sll(ucast(p_lh), 16));
	res = add(res, sll(ucast(p_hl), 16));
	res = add(res, sll(ucast(p_hh), 32));
	
	return res;
}  


int_64_t mult(register long int v1, register long int v2) /* signed 32-b multiplication z = x * y */ 
{
	int_64_t product;
	unsigned long int multiplicand, multiplier; /* long int force */
	int s = 0;
	 /* product negative when signs differ */
 	s = (v1 < 0) ^ (v2 < 0);
        
	/* compute magnitudes */
	multiplicand = abs(v1);
	multiplier = abs(v2);
	product = umult(multiplicand, multiplier);    
	if(s) {
	   product = neg(product);	
	}
	return product;
}


void sum_rot_block_row(ufp27p5_t powers[4][24])
{
    int i, w;
    fp15p17_t fp_cospart, fp_sinpart; /* FIXED-POINT */
     
    /* Foreach DFT wave ... */
    for (w = 0; w < 4; w++)
    {   /* Initialize accumulators */
	  fp_cospart = 0; /* FIXED-POINT */
	  fp_sinpart = 0; /* FIXED-POINT */
	  
	  /* Accumulate cos and sin components of DFT. */
	  for(i = 0; i < 24; i++) {  
	      /* Each rotated row sum is multiplied by its corresponding cos and sin point in DFT wave */ 
	      fp_cospart += mulfp15p17(itofp15p17(rowsums[i]), dft_waves_cos[i + (w * 24)]);		
	      fp_sinpart += mulfp15p17(itofp15p17(rowsums[i]), dft_waves_sin[i + (w * 24)]);
	  }
	  /* Power is the sum of the squared cos and sin components */
	 powers[w][0] = mulfp27p5(fp_cospart>>12, fp_cospart>>12) + mulfp27p5(fp_sinpart>>12, fp_sinpart>>12); /* FIXED-POINT */  
    }  
}



int main(void) 
{
    ufp27p5_t powers[4][24];
	int i;
	puts("dft Test Started\n");

    /* call sum_rot_block for row in direction 0 */
    sum_rot_block_row(powers);
 
 	rvex_succeed("dft Test Finished\n");
    return 0;
}
 

int dft_waves_cos[96] = {131072,
126606,
113512,
92683,
65537,
33926,
3,
-33921,
-65532,
-92679,
-113509,
-126605,
-131072,
-126608,
-113516,
-92689,
-65544,
-33934,
-11,
33913,
65526,
92673,
113505,
126602,
131072,
113512,
65537,
3,
-65532,
-113509,
-131072,
-113516,
-65544,
-11,
65526,
113505,
131072,
113518,
65549,
16,
-65521,
-113503,
-131072,
-113523,
-65556,
-24,
65514,
113499,
131072,
92683,
3,
-92679,
-131072,
-92689,
-11,
92673,
131072,
92692,
16,
-92669,
-131072,
-92698,
-24,
92664,
131071,
92701,
29,
-92660,
-131072,
-92707,
-37,
92654,
131072,
65537,
-65532,
-131072,
-65544,
65526,
131072,
65549,
-65521,
-131072,
-65556,
65514,
131071,
65560,
-65510,
-131072,
-65567,
65503,
131071,
65571,
-65499,
-131072,
-65578,
65492 };

int dft_waves_sin[96] = {0,
33923,
65535,
92680,
113510,
126605,
131071,
126606,
113514,
92685,
65540,
33929,
6,
-33917,
-65530,
-92676,
-113508,
-126604,
-131072,
-126609,
-113518,
-92691,
-65547,
-33937,
0,
65535,
113510,
131071,
113514,
65540,
6,
-65530,
-113508,
-131072,
-113518,
-65547,
-14,
65523,
113504,
131071,
113520,
65552,
19,
-65518,
-113501,
-131072,
-113524,
-65558,
0,
92680,
131071,
92685,
6,
-92676,
-131072,
-92691,
-14,
92671,
131071,
92694,
19,
-92667,
-131072,
-92700,
-27,
92662,
131071,
92704,
32,
-92658,
-131072,
-92709,
0,
113510,
113514,
6,
-113508,
-113518,
-14,
113504,
113520,
19,
-113501,
-113524,
-27,
113497,
113527,
32,
-113495,
-113531,
-40,
113491,
113533,
45,
-113488,
-113537 };


