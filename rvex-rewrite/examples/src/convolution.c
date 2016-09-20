

/*
 * Framebuffer code
 *
 */

/*
Note; we need to use another assembler when running on the xstsim simulator versus the static stopbit core.
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
#define imageHeight 32

//declare image buffers 
//int image[imageWidth][imageHeight]; 
//int result[imageWidth][imageHeight];

//Choose kernel here
/* Note: This matrix needs values between 0 and 256 (instead of 0 and 1 floating point) */
//#define DEFAULT
//#define EDGE
#define BLUR

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

#ifdef DEFAULT
#if filterWidth == 5
int filter[filterWidth][filterHeight] =
{
     0, 0, 0, 0, 0,
     0, 0, 0, 0, 0,
     0, 0, 256, 0, 0,
     0, 0, 0, 0, 0,
     0, 0, 0, 0, 0,
};
#endif
#if filterWidth == 3
int filter[filterWidth][filterHeight] =
{
     0, 0, 0,
     0, 256, 0,
     0, 0, 0,
};
#endif
#endif

#ifdef EDGE

int filter[filterWidth][filterHeight] =
{
     -256, -256, -256,
     -256, 2048, -256,
     -256, -256, -256
};
/*
int filter[filterWidth][filterHeight] =
{
     -1, -1, -1,
     -1, 8, -1,
     -1, -1, -1
};
*/
#endif

#ifdef BLUR
#if filterWidth == 3

#else
#if filterWidth == 5
int filter[filterWidth][filterHeight] =
{
     32, 32, 32, 32, 32,
     32, 32, 32, 32, 32,
     32, 32, 32, 32, 32,
     32, 32, 32, 32, 32,
     32, 32, 32, 32, 32
};
#else
int filter[filterWidth][filterHeight] =
{
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32,
     32, 32, 32, 32, 32, 32, 32
};
#endif
#endif
/*
int filter[filterWidth][filterHeight] =
{
     1, 1, 1,
     1, 1, 1,
     1, 1, 1
};
*/
#endif

#if USE_FACTOR
int factor = 256;
int bias = 0;
#endif


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

char strbuf[12];
int main()
{
    unsigned int* framebuffer = (unsigned int*)0x800000 + (imageWidth*imageHeight);
    unsigned int* image = (unsigned int*)0x800000;
    int timerread;
	//puts("convolution starting\n");
	//init_vga();

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


	//puts("Finished\n");
	//tohex(strbuf, CR_CNT - timerread);
	//puts(strbuf);

    return 0;
}

