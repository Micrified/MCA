#include "common.h"

//#define DEBUG

/* The following code is from Iodev.org, modified for integer */
#define filterWidth 3
#define filterHeight 3
#define imageWidth 64
#define imageHeight 64

//declare image buffers 
unsigned int median_image[imageWidth*imageHeight] = {
#include "lena_64x64.inc"
};
unsigned int median_result[imageWidth*imageHeight];

//Note: this code must be compiled with the -autoline flag when using the HP compiler
inline void swap(unsigned char *a, unsigned char *b)
{
	unsigned char tmp = *a;
	*a = *b;
	*b = tmp;
}

char strbuf[12];
int main()
{
    unsigned int* framebuffer = median_result;
    unsigned int* image = median_image;

	//puts("median starting\n");
	//init_vga();

    int i, j, x, y, filterX, filterY, imageX, imageY;

#ifdef DEBUG
    int runs;
#endif

	register unsigned int window[filterWidth*filterHeight];
	register currChan;




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
    for(y = filterHeight/2; y < imageHeight-(filterHeight/2); y++)
    for(x = filterWidth /2; x < imageWidth- (filterWidth /2); x++)
    {

            /* when using 3 windows: */
/*
        for(filterX = 0; filterX < filterWidth; filterX++)
//        #pragma unroll(4)
        for(filterY = 0; filterY < filterHeight; filterY++)
        {
            imageX = (x - filterWidth / 2 + filterX);// % imageWidth;
            imageY = (y - filterHeight / 2 + filterY);// % imageHeight;
            
            window[(filterX*filterWidth)+filterY] = image[imageX + (imageY*imageWidth)];
            

        	windowr[(filterX*filterWidth)+filterY] = (unsigned char)((image[imageX + (imageY*imageWidth)]>>16)&0xff);
	       	windowg[(filterX*filterWidth)+filterY] = (unsigned char)((image[imageX + (imageY*imageWidth)]>>8)&0xff);
        	windowb[(filterX*filterWidth)+filterY] = (unsigned char)(image[imageX + (imageY*imageWidth)]&0xff);
        }
*/
		/*
		 * Maybe because of the register keyword, the compiler doesn't see the possible reuse. 
		 * I'd have to explicitly write that out.
		 */
		window[0] = image[x-1 + (y-1*imageWidth)];
		window[1] = image[x   + (y-1*imageWidth)];
		window[2] = image[x+1 + (y-1*imageWidth)];
		window[3] = image[x-1 + (y  *imageWidth)];
		window[4] = image[x   + (y  *imageWidth)];
		window[5] = image[x+1 + (y  *imageWidth)];
		window[6] = image[x-1 + (y+1*imageWidth)];
		window[7] = image[x   + (y+1*imageWidth)];
		window[8] = image[x+1 + (y+1*imageWidth)];
		
        //now for all 3 channels, sort the array and pick the median value

		/*
		 * We're using 1 window, sort it 3 times.
		 * After each run, move the median value into the output
		 * and remove the higher bits from the values.
		 * We really want to keep the window in registers, so we write this out fully.
		 * To improve ILP, we'll write the sorting algorithm a bit differently from pure bubblesort (odd-even).
		 */
		 
		 currChan = 0x00ff0000; //start with red, the highest indexed bits
		 for (i = 0; i < 3; i++)
		 {
		 	
#ifdef DEBUG
puts("window:\n");
	tohex(strbuf, window[0]);
	puts(strbuf);
	tohex(strbuf, window[1]);
	puts(strbuf);
	tohex(strbuf, window[2]);
	puts(strbuf);
	tohex(strbuf, window[3]);
	puts(strbuf);
	tohex(strbuf, window[4]);
	puts(strbuf);
	tohex(strbuf, window[5]);
	puts(strbuf);
	tohex(strbuf, window[6]);
	puts(strbuf);
	tohex(strbuf, window[7]);
	puts(strbuf);
	tohex(strbuf, window[8]);
	puts(strbuf);
#endif //debug
		 	//sort
//		 	#pragma unroll (4)
		 	for (j = 0; j < 4; j++)
		 	{
		 		unsigned int tmp;
		 		//even
		 		if (window[0] > window[1])
		 		{
		 			tmp = window[0];
		 			window[0] = window[1];
		 			window[1] = tmp;
		 		}
		 		if (window[2] > window[3])
		 		{
		 			tmp = window[2];
		 			window[2] = window[3];
		 			window[3] = tmp;
		 		}
		 		if (window[4] > window[5])
		 		{
		 			tmp = window[4];
		 			window[4] = window[5];
		 			window[5] = tmp;
		 		}
		 		if (window[6] > window[7])
		 		{
		 			tmp = window[6];
		 			window[6] = window[7];
		 			window[7] = tmp;
		 		}
		 		
		 		//odd
		 		if (window[1] > window[2])
		 		{
		 			tmp = window[1];
		 			window[1] = window[2];
		 			window[2] = tmp;
		 		}
		 		if (window[3] > window[4])
		 		{
		 			tmp = window[3];
		 			window[3] = window[4];
		 			window[4] = tmp;
		 		}
		 		if (window[5] > window[6])
		 		{
		 			tmp = window[5];
		 			window[5] = window[6];
		 			window[6] = tmp;
		 		}
		 		if (window[7] > window[8])
		 		{
		 			tmp = window[7];
		 			window[7] = window[8];
		 			window[8] = tmp;
		 		}
		 	
		 	}
		 	
#ifdef DEBUG
puts("window sorted:\n");
	tohex(strbuf, window[0]);
	puts(strbuf);
	tohex(strbuf, window[1]);
	puts(strbuf);
	tohex(strbuf, window[2]);
	puts(strbuf);
	tohex(strbuf, window[3]);
	puts(strbuf);
	tohex(strbuf, window[4]);
	puts(strbuf);
	tohex(strbuf, window[5]);
	puts(strbuf);
	tohex(strbuf, window[6]);
	puts(strbuf);
	tohex(strbuf, window[7]);
	puts(strbuf);
	tohex(strbuf, window[8]);
	puts(strbuf);

#endif //debug
		 	
		 	//write channel into output
		 	framebuffer[(y*imageWidth)+x] |= window[4]; //this assumes the output array has been cleared
		 	
		 	//if (i ==2) break; //the rest is not necessary for the last channel, but this doesn't speed up the code. I guess the compiler sees it.
		 	
		 	//remove current channel from window
		 	window[0] &= ~currChan;
		 	window[1] &= ~currChan;
		 	window[2] &= ~currChan;
		 	window[3] &= ~currChan;
		 	window[4] &= ~currChan;
		 	window[5] &= ~currChan;
		 	window[6] &= ~currChan;
		 	window[7] &= ~currChan;
		 	window[8] &= ~currChan;
		 	
		 	//next channel
		 	currChan >>= 8;
		 }


/* When using 3 windows:

		for (j = 0; j < (filterHeight*filterWidth)-1; j++)
		for (i = 0; i < (filterHeight*filterWidth)-1; i++)
		{
#define USE_SWAP //Using swap is faster (don't know why)
#ifdef USE_SWAP
			if (windowr[i] > windowr[i+1])
				swap(&windowr[i], &windowr[i+1]);
			if (windowg[i] > windowg[i+1])
				swap(&windowr[i], &windowr[i+1]);
			if (windowb[i] > windowb[i+1])
				swap(&windowr[i], &windowr[i+1]);
#else
			unsigned char tr, tg, tb;
			if (windowr[i] > windowr[i+1])
			{
				tr = windowr[i];
				windowr[i] = windowr[i+1];
				windowr[i+1] = tr;
			}
			if (windowg[i] > windowg[i+1])
			{
				tg = windowg[i];
				windowg[i] = windowg[i+1];
				windowg[i+1] = tg;
			}
			if (windowb[i] > windowb[i+1])
			{
				tb = windowb[i];
				windowb[i] = windowb[i+1];
				windowb[i+1] = tb;
			}
#endif
		}
*/

		

        /* when using 3 windows
        framebuffer[(y*imageWidth)+x] = windowr[(filterWidth*filterHeight)/2]<<16
        | windowg[(filterWidth*filterHeight)/2]<<8
        | windowb[(filterWidth*filterHeight)/2];
        */
    }
#ifdef DEBUG
    } //runs
#endif

	puts("Median Finished\n");

    return 0;
}

