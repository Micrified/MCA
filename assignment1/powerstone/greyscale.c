#include "common.h"


#define imageWidth 64
#define imageHeight 64

//#define DEBUG

unsigned int grey_framebuffer[imageWidth*imageHeight];
unsigned int grey_image[imageWidth*imageHeight];


inline int max(int a, int b)
{
	if (a > b) return a;
	else return b;
}

inline int min(int a, int b)
{
	if (a < b) return a;
	else return b;
}

int main()
{

    int i, x, y, filterX, filterY, imageX, imageY;
    
    unsigned int* framebuffer = grey_framebuffer;
    unsigned int* image = grey_image;

#ifdef DEBUG
    int runs;
#endif

	//puts("greyscale starting\n");


	/* First write a test screen */
/*
	for (i = 0; i < 640*160; i++)
	{
		image[i] = 0x00FF0000 - ((((i%640)/3)&0xff)<<16);
	}
	for (; i < 640*320; i++)
	{
		image[i] = 0x0000FF00 - ((((i%640)/3)&0xff)<<8);
	}
	for (; i < 640*480; i++)
	{
		image[i] = 0x000000FF - (((i%640)/3)&0xff);
	}
*/


	//Clear the output image
//	#pragma unroll(4)
	for (i = 0; i < (imageWidth*imageHeight); i++)
		framebuffer[i] = 0;


#ifdef DEBUG
    for (runs = 0; runs < 2; runs++){
#endif
    //apply the filter
    for(y = 0; y < imageHeight; y++)
    for(x = 0; x < imageWidth; x++)
    {
    	unsigned int greyscale;
    	unsigned int rgb = image[x + (y*imageWidth)];
        unsigned char highest = (unsigned int) (max(max(rgb&0xff, (rgb>>8)&0xff), (rgb>>16)&0xff) & 0xff);

        
#ifdef DEBUG
if(runs){
        puts("RGB values:\n");
        tohex(strbuf, rgb);
        puts(strbuf);
}
#endif

		greyscale = highest <<16 | highest <<8 | highest;
        framebuffer[(y*imageWidth)+x] = greyscale;
        
#ifdef DEBUG
if(runs){
        puts("Greyscale:\n");
        tohex(strbuf, greyscale);
        puts(strbuf);
}
#endif

    }
#ifdef DEBUG
    } //runs
#endif


	puts("Greyscale Finished\n");

    return 0;
}


