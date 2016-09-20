void _bcopy(char *src, char *dest, int size)
{
	int i;
	for (i = 0; i < size; i++)
		dest[i] = src[i];
}
