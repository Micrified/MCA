#include "common.h"


//#define DEBUG

/* The following code is from Iodev.org, modified for integer */
#define filterWidth 3
#define filterHeight 3
#define imageWidth 64
#define imageHeight 64

//declare image buffers 
unsigned int conv3_image[imageWidth*imageHeight] = {
#include "lena_64x64.inc"
};
unsigned int conv3_result[imageWidth*imageHeight];



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
	unsigned int* framebuffer = conv3_result;
	unsigned int* image = conv3_image;
    //unsigned int* framebuffer = (unsigned int*)0x800000 + (imageWidth*imageHeight);
    //unsigned int* image = (unsigned int*)0x800000;
    int timerread;

    int i, x, y, filterX, filterY, imageX, imageY;

	register int filter[filterWidth][filterHeight] =
	{
		 32, 32, 32,
		 32, 32, 32,
		 32, 32, 32
	};

#ifdef DEBUG
    int runs;
#endif


	//puts("convolution starting\n");

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
    for(x = filterWidth /2; x < imageWidth -(filterWidth /2); x++)
    {
        int red = 0, green = 0, blue = 0;

        //multiply every value of the filter with corresponding image pixel
/*
        for(filterX = 0; filterX < filterWidth; filterX++)
//        #pragma unroll(4)
        for(filterY = 0; filterY < filterHeight; filterY++)
        {
//            imageX = (x - filterWidth / 2 + filterX + imageWidth) % imageWidth;
//            imageY = (y - filterHeight / 2 + filterY + imageHeight) % imageHeight;
            imageX = (x - filterWidth / 2 + filterX);// % imageWidth;
            imageY = (y - filterHeight / 2 + filterY);// % imageHeight;

            red   += (((signed int)((image[imageX + (imageY*imageWidth)]>>16)&0xFF)) * filter[filterX][filterY])/256;
            green += (((signed int)((image[imageX + (imageY*imageWidth)]>> 8)&0xFF)) * filter[filterX][filterY])/256;
            blue  +=  (((signed int)(image[imageX + (imageY*imageWidth)]     &0xFF)) * filter[filterX][filterY])/256;
*/
			/*
			 * We really want to keep the filter window in registers, so we write this out fully
			 */
            red   += (((signed int)((image[x-1 + (y-1*imageWidth)]>>16)&0xFF)) * filter[0][0])/256;
            green += (((signed int)((image[x-1 + (y-1*imageWidth)]>> 8)&0xFF)) * filter[0][0])/256;
            blue  +=  (((signed int)(image[x-1 + (y-1*imageWidth)]     &0xFF)) * filter[0][0])/256;
            
            red   += (((signed int)((image[x + (y-1*imageWidth)]>>16)&0xFF)) * filter[0][1])/256;
            green += (((signed int)((image[x + (y-1*imageWidth)]>> 8)&0xFF)) * filter[0][1])/256;
            blue  +=  (((signed int)(image[x + (y-1*imageWidth)]     &0xFF)) * filter[0][1])/256;
            
            red   += (((signed int)((image[x+1 + (y-1*imageWidth)]>>16)&0xFF)) * filter[0][2])/256;
            green += (((signed int)((image[x+1 + (y-1*imageWidth)]>> 8)&0xFF)) * filter[0][2])/256;
            blue  +=  (((signed int)(image[x+1 + (y-1*imageWidth)]     &0xFF)) * filter[0][2])/256;
            
            red   += (((signed int)((image[x-1 + (y*imageWidth)]>>16)&0xFF)) * filter[1][0])/256;
            green += (((signed int)((image[x-1 + (y*imageWidth)]>> 8)&0xFF)) * filter[1][0])/256;
            blue  +=  (((signed int)(image[x-1 + (y*imageWidth)]     &0xFF)) * filter[1][0])/256;
            
            red   += (((signed int)((image[x + (y*imageWidth)]>>16)&0xFF)) * filter[1][1])/256;
            green += (((signed int)((image[x + (y*imageWidth)]>> 8)&0xFF)) * filter[1][1])/256;
            blue  +=  (((signed int)(image[x + (y*imageWidth)]     &0xFF)) * filter[1][1])/256;
            
            red   += (((signed int)((image[x+1 + (y*imageWidth)]>>16)&0xFF)) * filter[1][2])/256;
            green += (((signed int)((image[x+1 + (y*imageWidth)]>> 8)&0xFF)) * filter[1][2])/256;
            blue  +=  (((signed int)(image[x+1 + (y*imageWidth)]     &0xFF)) * filter[1][2])/256;
            
            red   += (((signed int)((image[x-1 + (y+1*imageWidth)]>>16)&0xFF)) * filter[2][0])/256;
            green += (((signed int)((image[x-1 + (y+1*imageWidth)]>> 8)&0xFF)) * filter[2][0])/256;
            blue  +=  (((signed int)(image[x-1 + (y+1*imageWidth)]     &0xFF)) * filter[2][0])/256;
            
            red   += (((signed int)((image[x + (y+1*imageWidth)]>>16)&0xFF)) * filter[2][1])/256;
            green += (((signed int)((image[x + (y+1*imageWidth)]>> 8)&0xFF)) * filter[2][1])/256;
            blue  +=  (((signed int)(image[x + (y+1*imageWidth)]     &0xFF)) * filter[2][1])/256;
            
            red   += (((signed int)((image[x+1 + (y+1*imageWidth)]>>16)&0xFF)) * filter[2][2])/256;
            green += (((signed int)((image[x+1 + (y+1*imageWidth)]>> 8)&0xFF)) * filter[2][2])/256;
            blue  +=  (((signed int)(image[x+1 + (y+1*imageWidth)]     &0xFF)) * filter[2][2])/256;
            
#ifdef DEBUG
if(runs){
            puts("Old RGB:\n");
            tohex(strbuf, ((image[imageX + (imageY*imageWidth)]>>16)&0xFF));
            puts(strbuf);
            tohex(strbuf, ((image[imageX + (imageY*imageWidth)]>> 8)&0xFF));
            puts(strbuf);
            tohex(strbuf, (image[imageX + (imageY*imageWidth)]&0xFF));
            puts(strbuf);

            puts("RGB additions:\n");
            tohex(strbuf, red);
            puts(strbuf);
            tohex(strbuf, green);
            puts(strbuf);
            tohex(strbuf, blue);
            puts(strbuf);
}
#endif

//        }
#ifdef DEBUG
if(runs){
        puts("RGB values:\n");
        tohex(strbuf, red);
        puts(strbuf);
        tohex(strbuf, green);
        puts(strbuf);
        tohex(strbuf, blue);
        puts(strbuf);
}
#endif

#if USE_FACTOR
        //truncate values smaller than zero and larger than 255
        framebuffer[x][y] = min(max(int(factor * red + bias), 0), 255)<<16
		| min(max(int(factor * green + bias), 0), 255)<<8
        | min(max(int(factor * blue + bias), 0), 255);
#else
        //truncate values smaller than zero and larger than 255
        framebuffer[(y*imageWidth)+x] = min(max(red, 0), 255)<<16
        | min(max(green, 0), 255)<<8
        | min(max(blue, 0), 255);
#endif //USE_FACTOR
    }
#ifdef DEBUG
    } //runs
#endif


	puts("Convolution 3x3 Finished\n");

    return 0;
}

