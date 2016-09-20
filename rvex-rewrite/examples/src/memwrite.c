/*
 * This doesnt do anything useful.
 *
 */

int main()
{
	int i;
	int a,b,c;
	int r;
	a = b = c = r = 0;
	for (i = 0; i < 1; i++)
	{
		a += i;
		b += 2*i;
		c += 3*i;
		r += turn(&a,&b,&c);
	}
	return r;
}



int turn(int *a, int *b, int *c)
{
	int tmp = *a;
	*a = *b;
	*b = *c;
	*c = tmp;
	return *a+*b+*c;
}

