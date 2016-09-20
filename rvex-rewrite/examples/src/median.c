

/*
 * Framebuffer code
 *
 */

#ifdef PLATFORM
#define FB_ADDRESS 0x400000
#else
#define FB_ADDRESS 0x20100000
#endif


#include "rvex.h"

//#define DEBUG

/* The following code is from Iodev.org, modified for integer */
#define filterWidth 3
#define filterHeight 3
#define imageWidth 64
#define imageHeight 64

//declare image buffers 
//int image[imageWidth][imageHeight]; 
//int result[imageWidth][imageHeight];


/* framebuffer stuff */


typedef  unsigned int __u32;

/*
 * from snapgear Linux:
 */

/* Interpretation of offset for color fields: All offsets are from the right,
 * inside a "pixel" value, which is exactly 'bits_per_pixel' wide (means: you
 * can use the offset as right argument to <<). A pixel afterwards is a bit
 * stream and is written to video memory as that unmodified. This implies
 * big-endian byte order if bits_per_pixel is greater than 8.
 */
struct fb_bitfield {
	__u32 offset;			/* beginning of bitfield	*/
	__u32 length;			/* length of bitfield		*/
	__u32 msb_right;		/* != 0 : Most significant bit is */
					/* right */
};

struct fb_var_screeninfo {
	__u32 xres;			/* visible resolution		*/
	__u32 yres;
	__u32 xres_virtual;		/* virtual resolution		*/
	__u32 yres_virtual;
	__u32 xoffset;			/* offset from virtual to visible */
	__u32 yoffset;			/* resolution			*/

	__u32 bits_per_pixel;		/* guess what			*/
	__u32 grayscale;		/* != 0 Graylevels instead of colors */

	struct fb_bitfield red;		/* bitfield in fb mem if true color, */
	struct fb_bitfield green;	/* else only length is significant */
	struct fb_bitfield blue;
	struct fb_bitfield transp;	/* transparency			*/

	__u32 nonstd;			/* != 0 Non standard pixel format */

	__u32 activate;			/* see FB_ACTIVATE_*		*/

	__u32 height;			/* height of picture in mm    */
	__u32 width;			/* width of picture in mm     */

	__u32 accel_flags;		/* (OBSOLETE) see fb_info.flags */

	/* Timing: All values in pixclocks, except pixclock (of course) */
	__u32 pixclock;			/* pixel clock in ps (pico seconds) */
	__u32 left_margin;		/* time from sync to picture	*/
	__u32 right_margin;		/* time from picture to sync	*/
	__u32 upper_margin;		/* time from sync to picture	*/
	__u32 lower_margin;
	__u32 hsync_len;		/* length of horizontal sync	*/
	__u32 vsync_len;		/* length of vertical sync	*/
	__u32 sync;			/* see FB_SYNC_*		*/
	__u32 vmode;			/* see FB_VMODE_*		*/
	__u32 rotate;			/* angle we rotate counter clockwise */
	__u32 reserved[5];		/* Reserved for future compatibility */
};



typedef struct {
  volatile unsigned int status; 				/* 0x00 */
  volatile unsigned int video_length; 	/* 0x04 */
  volatile unsigned int front_porch;		/* 0x08 */
  volatile unsigned int sync_length;		/* 0x0c */
  volatile unsigned int line_length;		/* 0x10 */
  volatile unsigned int fb_pos;					/* 0x14 */
  volatile unsigned int clk_vector[4];	/* 0x18 */
  volatile unsigned int clut;						/* 0x28 */
} LEON3_GRVGA_Regs_Map;



void init_vga()
{
	LEON3_GRVGA_Regs_Map *regs = (LEON3_GRVGA_Regs_Map*)0x80000600;
	int clk_sel = -1, func = 0, i;
	struct fb_var_screeninfo init_data;
	
	init_data.xres =			640,
    init_data.yres =			480,
    init_data.xres_virtual =	640,
    init_data.yres_virtual =	480,
    init_data.pixclock = 	    40000,
    init_data.left_margin =		48,
    init_data.right_margin =	16,
    init_data.upper_margin =	31,
    init_data.lower_margin =	11,
    init_data.hsync_len =		96,
    init_data.vsync_len =		2,
	
	init_data.bits_per_pixel = 8;

	regs->video_length = ((init_data.yres - 1) << 16)
			+ (init_data.xres - 1);
	regs->front_porch = (init_data.lower_margin << 16)
			+ (init_data.right_margin);
	regs->sync_length = (init_data.vsync_len << 16)
			+ (init_data.hsync_len);
	regs->line_length = ((init_data.yres
			+ init_data.lower_margin + init_data.upper_margin
			+ init_data.vsync_len - 1) << 16)
			+ (init_data.xres + init_data.right_margin
					+ init_data.left_margin
					+ init_data.hsync_len - 1);

	regs->fb_pos = 0x400000;
	clk_sel = 0; //3 for modelsim, 0 for board
	func = 3;
	regs->status = ((clk_sel << 6) | (func << 4)) | 1;

}

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

inline void swap(unsigned char *a, unsigned char *b)
{
	unsigned char tmp = *a;
	*a = *b;
	*b = tmp;
}

    char strbuf[12];
int main()
{
    unsigned int* framebuffer = (unsigned int*)0x800000 + (imageWidth*imageHeight);
    unsigned int* image = (unsigned int*)0x800000;
    int timerread;
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
	//timerread = CR_CNT;


	//Clear the output image
/*
	#pragma unroll(4)
	for (i = 0; i < (imageWidth*imageHeight); i++)
		framebuffer[i] = 0;
*/
    //load the image into the buffer
    //loadBMP("pics/photo3.bmp", image[0], imageWidth , imageHeight);
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
		 * To improve ILP, we'll write the sorting algorithm a bit differently from pure bubblesort.
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
		 	#pragma unroll (4)
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

	//puts("Finished\n");
	//tohex(strbuf, CR_CNT - timerread);
	//puts(strbuf);

    return 0;
}

