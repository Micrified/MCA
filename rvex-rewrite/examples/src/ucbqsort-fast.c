unsigned char SortArr[20] = {
  57, 126, 223, 44, 11, 138, 251, 232, 143, 86, 215, 60, 83, 30, 115, 48, 87, 46, 49, 164
};

const unsigned char SortedArr[20] = {
  11, 30, 44, 46, 48, 49, 57, 60, 83, 86, 87, 115, 126, 138, 143, 164, 215, 223, 232, 251
};

void QSORT(char *base, int n, int size, int (*compar) ());
int compare(char *n1, char *n2)
{
  return (*((unsigned char *) n1) - *((unsigned char *) n2));
}
int main()
{
	int j;
	QSORT((char *) SortArr, (int) 20, sizeof(unsigned char), compare);
	for (j = 0; j < 20; j++) {
		if (SortArr[j] != SortedArr[j]) {
			rvex_fail("ucbqsort-fast: failed\n");
			return 1;
		}
	}
	rvex_succeed("ucbqsort-fast: success\n");
	return 0;
}
static int (*qcmp) ();
static int qsz;
static int thresh;
static int mthresh;
static void qst(char *, char *);
void QSORT(base, n, size, compar)
     char *base;
     int n;
     int size;
     int (*compar) ();
{
  register char c, *i, *j, *lo, *hi;
  char *min, *max;
  if (n <= 1)
    return;
  qsz = size;
  qcmp = compar;
  thresh = qsz * 4;
  mthresh = qsz * 6;
  max = base + n * qsz;
  if (n >= 4)
    {
      qst(base, max);
      hi = base + thresh;
    } 
  else
    {
      hi = max;
    }
  for (j = lo = base; (lo += qsz) < hi;)
    if ((*qcmp) (j, lo) > 0)
      j = lo;
  if (j != base)
    {
      for (i = base, hi = base + qsz; i < hi;)
	{
	  c = *j;
	  *j++ = *i;
	  *i++ = c;
	}
    }
  for (min = base; (hi = min += qsz) < max;)
    {
      while ((*qcmp) (hi -= qsz, min) > 0)
	;
      if ((hi += qsz) != min)
	{
	  for (lo = min + qsz; --lo >= min;)
	    {
	      c = *lo;
	      for (i = j = lo; (j -= qsz) >= hi; i = j)
		*i = *j;
	      *i = c;
	    }
	}
    }
}
static
void qst(base, max)
     char *base, *max;
{
  register char c, *i, *j, *jj;
  register int ii;
  char *mid, *tmp;
  int lo, hi;
  lo = max - base;
  do
    {
      mid = i = base + qsz * ((lo / qsz) >> 1);
      if (lo >= mthresh)
	{
	  j = ((*qcmp) ((jj = base), i) > 0 ? jj : i);
	  if ((*qcmp) (j, (tmp = max - qsz)) > 0)
	    {
	      j = (j == jj ? i : jj);
	      if ((*qcmp) (j, tmp) < 0)
		j = tmp;
	    }
	  if (j != i)
	    {
	      ii = qsz;
	      do
		{
		  c = *i;
		  *i++ = *j;
		  *j++ = c;
		}
	      while (--ii);
	    }
	}
      for (i = base, j = max - qsz;;)
	{
	  while (i < mid && (*qcmp) (i, mid) <= 0)
            i += qsz;
	  while (j > mid)
	    {
	      if ((*qcmp) (mid, j) <= 0)
		{
		  j -= qsz;
		  continue;
		}
	      tmp = i + qsz;
	      if (i == mid)
		{
		  mid = jj = j;
		} 
	      else
		{
		  jj = j;
		  j -= qsz;
		}
	      goto swap;
	    }
	  if (i == mid)
	    {
	      break;
	    } 
	  else
	    {
	      jj = mid;
	      tmp = mid = i;
	      j -= qsz;
	    }
	swap:
	  ii = qsz;
	  do
	    {
	      c = *i;
	      *i++ = *jj;
	      *jj++ = c;
	    }
	  while (--ii);
	  i = tmp;
	}
      i = (j = mid) + qsz;
      if ((lo = j - base) <= (hi = max - i))
	{
	  if (lo >= thresh)
            qst(base, j);
	  base = i;
	  lo = hi;
	} 
      else
	{
	  if (hi >= thresh)
            qst(i, max);
	  max = j;
	}
    }
  while (lo >= thresh);
}
