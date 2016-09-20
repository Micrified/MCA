#include "rvex.h"

typedef long restricted_long;

typedef short restricted_DSPshort;

typedef short DSPshort;		/* DSP integer */

typedef unsigned short DSPushort;	/* DSP unsigned integer */

typedef double DSPfract;	/* DSP fixed-point fractional */

typedef long DSPlong;		/* DSP long (32 bits) */

#define MULT32X32(a,b) (((((long)((a)>>16))*((long)((b)>>16)))<<1) +((((long)((a)>>16))*((long)((unsigned short) b)))>>15) + ((((long)((b)>>16))*((long)((unsigned short)a)))>>15))	/*AG54 */



#define N 256
#define NCHANS 6
#define FFTN (N/2)
#define FFTNLG2M3 4
#define NACMOD 8
#define NPCMCHANS 6

#define LEFT 0
#define CNTR 1
#define RGHT 2
#define LSUR 3
#define RSUR 4
#define LFE 5
#define MSUR 3
#define NONE -1

/*AG55*/
long zcos1_fixed[N / 2] = {
  -2147481121, -2147278995, -2146753496, -2145904704, -2144732747,
  -2143237801, -2141420092, -2139279892,
  -2136817525, -2134033360, -2130927818, -2127501367, -2123754521,
  -2119687846, -2115301954, -2110597505,
  -2105575207, -2100235818, -2094580141, -2088609028, -2082323378,
  -2075724138, -2068812302, -2061588910,
  -2054055050, -2046211857, -2038060512, -2029602243, -2020838323,
  -2011770072, -2002398856, -1992726086,
  -1982753219, -1972481757, -1961913246, -1951049278, -1939891490,
  -1928441560, -1916701215, -1904672221,
  -1892356391, -1879755579, -1866871683, -1853706643, -1840262441,
  -1826541102, -1812544693, -1798275322,
  -1783735137, -1768926328, -1753851125, -1738511799, -1722910659,
  -1707050055, -1690932376, -1674560048,
  -1657935538, -1641061349, -1623940022, -1606574136, -1588966305,
  -1571119182, -1553035455, -1534717846,
  -1516169114, -1497392052, -1478389489, -1459164286, -1439719338,
  -1420057573, -1400181953, -1380095471,
  -1359801152, -1339302051, -1318601257, -1297701886, -1276607086,
  -1255320033, -1233843934, -1212182023,
  -1190337562, -1168313840, -1146114174, -1123741907, -1101200410,
  -1078493075, -1055623324, -1032594599,
  -1009410370, -986074127, -962589385, -938959680, -915188572, -891279639,
  -867236484, -843062725, -818762004,
  -794337981, -769794334, -745134758, -720362968, -695482693, -670497682,
  -645411696, -620228513, -594951927,
  -569585742, -544133781, -518599874, -492987869, -467301621, -441544999,
  -415721883, -389836160, -363891729,
  -337892498, -311842381, -285745301, -259605190, -233425983, -207211623,
  -180966058, -154693239, -128397125,
  -102081674, -75750851, -49408619, -23058947
};



/*AG55*/
long zsin1_fixed[N / 2] = {
  -3294197, -29646846, -55995030, -82334781, -108662133, -134973121,
  -161263783, -187530158, -213768293,
  -239974235, -266144037, -292273759, -318359466, -344397229, -370383127,
  -396313247, -422183683, -447990540,
  -473729932, -499397981, -524990823, -550504603, -575935480, -601279622,
  -626533214, -651692452, -676753548,
  -701712728, -726566232, -751310317, -775941259, -800455346, -824848887,
  -849118210, -873259658, -897269597,
  -921144410, -944880502, -968474299, -991922247, -1015220815, -1038366495,
  -1061355800, -1084185270,
  -1106851464, -1129350972, -1151680403, -1173836395, -1195815612,
  -1217614743, -1239230506, -1260659645,
  -1281898934, -1302945174, -1323795194, -1344445856, -1364894050,
  -1385136695, -1405170744, -1424993180,
  -1444601016, -1463991301, -1483161115, -1502107569, -1520827812,
  -1539319024, -1557578420, -1575603250,
  -1593390801, -1610938392, -1628243383, -1645303165, -1662115171,
  -1678676869, -1694985764, -1711039401,
  -1726835361, -1742371266, -1757644777, -1772653592, -1787395453,
  -1801868138, -1816069469, -1829997306,
  -1843649553, -1857024152, -1870119091, -1882932396, -1895462139,
  -1907706432, -1919663432, -1931331337,
  -1942708391, -1953792881, -1964583136, -1975077532, -1985274489,
  -1995172471, -2004769987, -2014065592,
  -2023057886, -2031745515, -2040127171, -2048201591, -2055967560,
  -2063423907, -2070569510, -2077403294,
  -2083924228, -2090131330, -2096023667, -2101600350, -2106860539,
  -2111803444, -2116428318, -2120734466,
  -2124721240, -2128388038, -2131734308, -2134759548, -2137463300,
  -2139845158, -2141904764, -2143641806,
  -2145056024, -2146147205, -2146915183, -2147359844
};

/*AG55*/
long zcos2_fixed[N / 4] = {
  -2147473541, -2146665075, -2144563538, -2141170197, -2136487094,
  -2130517052, -2123263665, -2114731305,
  -2104925109, -2093850984, -2081515603, -2067926394, -2053091544,
  -2037019988, -2019721407, -2001206222,
  -1981485585, -1960571375, -1938476190, -1915213340, -1890796836,
  -1865241388, -1838562387, -1810775906,
  -1781898681, -1751948107, -1720942224, -1688899711, -1655839867,
  -1621782607, -1586748446, -1550758488,
  -1513834410, -1475998455, -1437273414, -1397682613, -1357249900,
  -1315999631, -1273956653, -1231146290,
  -1187594332, -1143327011, -1098370992, -1052753356, -1006501581, -959643527,
  -912207419, -864221832,
  -815715669, -766718151, -717258789, -667367378, -617073970, -566408860,
  -515402566, -464085812, -412489511,
  -360644742, -308582733, -256334846, -203932553, -151407418, -98791081,
  -46115236
};

/*AG55*/
long zsin2_fixed[N / 4] = {
  -6588386, -59288041, -111951983, -164548489, -217045877, -269412525,
  -321616889, -373627523, -425413097,
  -476942419, -528184448, -579108319, -629683357, -679879097, -729665303,
  -779011986, -827889421, -876268167,
  -924119081, -971413341, -1018122458, -1064218296, -1109673088, -1154459455,
  -1198550419, -1241919421,
  -1284540337, -1326387494, -1367435684, -1407660183, -1447036759,
  -1485541695, -1523151796, -1559844408,
  -1595597427, -1630389318, -1664199124, -1697006478, -1728791619,
  -1759535401, -1789219304, -1817825449,
  -1845336603, -1871736196, -1897008325, -1921137766, -1944109987,
  -1965911148, -1986528118, -2005948477,
  -2024160528, -2041153301, -2056916559, -2071440808, -2084717298,
  -2096738032, -2107495770, -2116984031,
  -2125197100, -2132130029, -2137778644, -2142139540, -2145210092, -2146988449
};

/* AG55*/
long xcos_fixed[N / 4] = {
  0x80000000, -2144896909, -2137142927, -2124240380, -2106220351, -2083126254,
  -2055013723, -2021950483,
  -1984016188, -1941302224, -1893911494, -1841958164, -1785567396,
  -1724875039, -1660027308, -1591180425,
  -1518500249, -1442161874, -1362349204, -1279254515, -1193077990,
  -1104027236, -1012316784, -918167571,
  -821806413, -723465451, -623381597, -521795963, -418953276, -315101294,
  -210490206, -105372028, 0,
  105372028, 210490206, 315101294, 418953276, 521795963, 623381597, 723465451,
  821806413, 918167571,
  1012316784, 1104027236, 1193077990, 1279254515, 1362349204, 1442161874,
  1518500249, 1591180425,
  1660027308, 1724875039, 1785567396, 1841958164, 1893911494, 1941302224,
  1984016188, 2021950483, 2055013723,
  2083126254, 2106220351, 2124240380, 2137142927, 2144896909
};


long xsin_fixed[N / 4] = {
  0, -105372028, -210490206, -315101294, -418953276, -521795963, -623381597,
  -723465451, -821806413,
  -918167571, -1012316784, -1104027236, -1193077990, -1279254515, -1362349204,
  -1442161874, -1518500249,
  -1591180425, -1660027308, -1724875039, -1785567396, -1841958164,
  -1893911494, -1941302224, -1984016188,
  -2021950483, -2055013723, -2083126254, -2106220351, -2124240380,
  -2137142927, -2144896909, 0x80000000,
  -2144896909, -2137142927, -2124240380, -2106220351, -2083126254,
  -2055013723, -2021950483, -1984016188,
  -1941302224, -1893911494, -1841958164, -1785567396, -1724875039,
  -1660027308, -1591180425, -1518500249,
  -1442161874, -1362349204, -1279254515, -1193077990, -1104027236,
  -1012316784, -918167571, -821806413,
  -723465451, -623381597, -521795963, -418953276, -315101294, -210490206,
  -105372028
};

short bitrev[N / 2] =
  { 0, 64, 32, 96, 16, 80, 48, 112, 8, 72, 40, 104, 24, 88, 56, 120,
  4, 68, 36, 100, 20, 84, 52, 116, 12, 76, 44, 108, 28, 92, 60, 124,
  2, 66, 34, 98, 18, 82, 50, 114, 10, 74, 42, 106, 26, 90, 58, 122,
  6, 70, 38, 102, 22, 86, 54, 118, 14, 78, 46, 110, 30, 94, 62, 126,
  1, 65, 33, 97, 17, 81, 49, 113, 9, 73, 41, 105, 25, 89, 57, 121,
  5, 69, 37, 101, 21, 85, 53, 117, 13, 77, 45, 109, 29, 93, 61, 125,
  3, 67, 35, 99, 19, 83, 51, 115, 11, 75, 43, 107, 27, 91, 59, 123,
  7, 71, 39, 103, 23, 87, 55, 119, 15, 79, 47, 111, 31, 95, 63, 127
};

short chantab[NACMOD][NPCMCHANS] = {
  {LEFT, RGHT, LFE, NONE, NONE, NONE},	/* 1+1 */
  {CNTR, LFE, NONE, NONE, NONE, NONE},	/* 1/0 */
  {LEFT, RGHT, LFE, NONE, NONE, NONE},	/* 2/0 */
  {LEFT, CNTR, RGHT, LFE, NONE, NONE},	/* 3/0 */
  {LEFT, RGHT, MSUR, LFE, NONE, NONE},	/* 2/1 */
  {LEFT, CNTR, RGHT, MSUR, LFE, NONE},	/* 3/1 */
  {LEFT, RGHT, LSUR, RSUR, LFE, NONE},	/* 2/2 */
  {LEFT, CNTR, RGHT, LSUR, RSUR, LFE}	/* 3/2 */

};
#define _DB_DOWN_MIX_ 1
/************************************************
                                  ITVER2
************************************************/
void
itver2 (short bswitch,
#ifndef _DB_DOWN_MIX_
		short appgainrng_i[NCHANS],
		short vcr_appgainrng[NCHANS],
#endif
		long *tcbuf,
		short acmod,
		short channum,
		int slct)
{



  long temp1, temp2, temp3, temp4, temp5, temp6, temp7, temp8, temp9, temp10,
    temp11, temp12;

  DSPshort i, j, l, m, bg, gp;
  DSPshort fftn, fftnlg2m3, nstep;
  restricted_long *fftr_buf, *ffti_buf;


#ifndef _DB_DOWN_MIX_
  int ActChan;
  int appgainrng;
#endif
  long arf, aif, brf, bif, crf, cif, drf, dif;


  long cr_fixed, ci_fixed;
  restricted_long wr_buf1[N], wi_buf1[N];


  register DSPshort shft_gp, shft_bg, i1, i2, i3, i4, l_plus_bg, fftnby2, mask_gp, neg_mask_gp, shft_fftnby2;	/*Added by Kaushik */
  unsigned long k, k1, total_ops, mask_fftnby2;	/*Added by Kaushik */


#ifndef _DB_DOWN_MIX_
#ifdef GNRNG
  appgainrng =
    (slct ==
     0) ? appgainrng_i[channum] : vcr_appgainrng[channum];
#else
  appgainrng = 0;
#endif /* GNRNG */
#endif /*  _DB_DOWN_MIX_ */


	/***     bswitch == 1 ***/
  if (bswitch)
    {
      fftn = (DSPshort) (FFTN / 2);
      fftnlg2m3 = (DSPshort) (FFTNLG2M3 - 1);
      nstep = 2;
      fftr_buf = wr_buf1;	/* point to correct buffer half */
      ffti_buf = wi_buf1 + fftn;

      /*  Do first in-place complex multiply & bit-reversal  */
      for (i = 0; i < N / 4; i++)
	{

	  cr_fixed = zcos2_fixed[i];
	  ci_fixed = zsin2_fixed[i];	/**Added by Kaushik **/



	  aif = (tcbuf[i << 2]);
	  arf = (tcbuf[((N / 4 - 1 - i) << 2) + 2]);
	  bif = (tcbuf[(i << 2) + 1]);
	  brf = (tcbuf[((N / 4 - 1 - i) << 2) + 3]);
	  /*AG55 */
	  temp1 = MULT32X32 (arf, cr_fixed);	/* do operation and assign to long */
	  temp2 = MULT32X32 (aif, ci_fixed);
	  temp3 = MULT32X32 (aif, cr_fixed);
	  temp4 = MULT32X32 (arf, ci_fixed);	/* 4 lines added by Kaushik */

	  temp5 = MULT32X32 (brf, cr_fixed);	/* do operation and assign to long */
	  temp6 = MULT32X32 (bif, ci_fixed);
	  temp7 = MULT32X32 (bif, cr_fixed);
	  temp8 = MULT32X32 (brf, ci_fixed);


	  j = bitrev[i << 1];

	  wr_buf1[j] = ((long) (temp1 - temp2));	/*AG54 */
	  wi_buf1[N / 4 + j] = ((long) (temp3 + temp4));	/*AG54 */
	  wr_buf1[N / 4 + j] = ((long) (temp5 - temp6));	/*AG54 */
	  wi_buf1[j] = ((long) (temp7 + temp8));	/*AG54 */

	}

    }
	/***     bswitch == 0 ***/
  else
    {
      fftn = (DSPshort) FFTN;
      fftnlg2m3 = (DSPshort) FFTNLG2M3;
      nstep = 1;
      fftr_buf = wr_buf1;	/* use a pointer */
      ffti_buf = wi_buf1;
      /*  Do first in-place complex multiply & bit-reversal  */
      for (i = 0; i < fftn; i++)
	{

	  /*      Do in-place complex multiply */
	  aif = (tcbuf[i << 1]);	/** 10 lines added by Kaushik **/
	  arf = (tcbuf[((N / 2 - 1 - i) << 1) + 1]);
	  cr_fixed = zcos1_fixed[i];
	  ci_fixed = zsin1_fixed[i];

	  /*AG55 */
	  temp1 = MULT32X32 (arf, cr_fixed);	/* do operation and assign to long */
	  temp2 = MULT32X32 (aif, ci_fixed);
	  temp3 = MULT32X32 (aif, cr_fixed);
	  temp4 = MULT32X32 (arf, ci_fixed);
	  /*      Do bit-reversal */
	  j = bitrev[i];

	  wr_buf1[j] = ((long) (temp1 - temp2));	/*AG54 */
	  wi_buf1[j] = ((long) (temp3 + temp4));	/*AG54 */


	}
    }

  /*  /////////////////////////////////////FFT///////////////////////////////////////////////////  */


	/**** Bitrev and first twiddle over **/

  bg = 4;			/* butterflies per group */
  gp = fftn >> 3;		/* fftn/8 *//* groups per pass */
  shft_gp = fftnlg2m3;		/*log2(gp) *//*Added by Kaushik */
  mask_gp = (0x7fff) >> (15 - shft_gp);
  neg_mask_gp = ~mask_gp;
  shft_bg = 3;			/*Added by Kaushik */
  fftnby2 = fftn >> 1;
  shft_fftnby2 = fftnlg2m3 + 2;
  mask_fftnby2 = (0x00007fffL) >> (15 - shft_fftnby2);
  total_ops = (fftnlg2m3 + 1) << (fftnlg2m3 + 2);
	/**This unrolling causes a 200 cycle decrease in the loop timing***/

#ifdef __ST200
#pragma precondition_amount(4)
#pragma unroll_amount(4,1)
#endif

  /*      Do first radix-4 pass */
  for (i = 0; i < fftn * nstep; i += 4)
    {
      m = ((i >= fftn) ? 1 : 0);

      fftr_buf = (m ? (wr_buf1 + fftn) : fftr_buf);
      ffti_buf = (m ? wi_buf1 : ffti_buf);

      l = ((i >= fftn) ? (i - fftn) : i);

      arf = (long) fftr_buf[l];
      aif = (long) ffti_buf[l];
      brf = (long) fftr_buf[l + 1];
      bif = (long) ffti_buf[l + 1];
      crf = (long) fftr_buf[l + 2];
      cif = (long) ffti_buf[l + 2];
      drf = (long) fftr_buf[l + 3];
      dif = (long) ffti_buf[l + 3];


      fftr_buf[l] = (long) (arf + brf + crf + drf);
      ffti_buf[l] = (long) (aif + bif + cif + dif);
      fftr_buf[l + 1] = (long) (arf - brf - cif + dif);
      ffti_buf[l + 1] = (long) (aif - bif + crf - drf);
      fftr_buf[l + 2] = (long) (arf + brf - crf - drf);
      ffti_buf[l + 2] = (long) (aif + bif - cif - dif);
      fftr_buf[l + 3] = (long) (arf - brf + cif - dif);
      ffti_buf[l + 3] = (long) (aif - bif - crf + drf);

    }				/* i */

  fftr_buf = wr_buf1;		/* use a pointer */
  ffti_buf = (bswitch ? (wi_buf1 + fftn) : wi_buf1);

#ifdef __ST200
#pragma precondition_amount(2)
#pragma unroll_amount(2,1)
#endif

  /*      Do all radix-2 passes except first two  */
  for (k1 = 0; k1 < total_ops * nstep; k1++)
    {
      m = ((k1 >= total_ops) ? 1 : 0);

      fftr_buf = (m ? (wr_buf1 + fftn) : fftr_buf);
      ffti_buf = (m ? wi_buf1 : ffti_buf);
      k = (m ? ((k1 - total_ops) >> shft_fftnby2) : (k1 >> shft_fftnby2));

      i2 = i3 = i1 = (DSPshort) ((m ?
				  ((k1 - total_ops) & mask_fftnby2) :
				  (k1 & mask_fftnby2)));

      i4 = ((nstep == 2) ? ((i1 & (neg_mask_gp >> k)) << 1) :	/* to be mult by nstep */
	    (i1 & (neg_mask_gp >> k)));	/* to be mult by nstep */

      l = (i2 >> (shft_gp - k)) + ((i3 & (mask_gp >> k)) << (shft_bg + k));	/*Added by Kaushik */

      l_plus_bg = l + (bg << k);

      cr_fixed = xcos_fixed[i4];
      ci_fixed = xsin_fixed[i4];

      arf = (long) fftr_buf[l];
      aif = (long) ffti_buf[l];
      brf = (long) fftr_buf[l_plus_bg];
      bif = (long) ffti_buf[l_plus_bg];

      /*AG55 */

      temp5 = MULT32X32 (brf, cr_fixed);
      temp6 = MULT32X32 (bif, ci_fixed);
      temp7 = MULT32X32 (brf, ci_fixed);
      temp8 = MULT32X32 (bif, cr_fixed);

      fftr_buf[l] = (long) (arf - temp5 + temp6);
      ffti_buf[l] = (long) (aif - temp7 - temp8);
      fftr_buf[l_plus_bg] = (long) (arf + temp5 - temp6);
      ffti_buf[l_plus_bg] = (long) (aif + temp7 + temp8);
    }				/* k1 */




  /*      Do complex multiply */
	/***     bswitch == 1 ***/
  if (bswitch)
    {
      for (i = 0; i < N / 4; i++)
	{
	  cr_fixed = zcos2_fixed[i];  /**Added by Kaushik ***/
	  ci_fixed = zsin2_fixed[i];	/**Added by Kaushik ***/

	  arf = (long) wr_buf1[i];
	  aif = (long) wi_buf1[N / 4 + i];

	  brf = (long) wr_buf1[N / 4 + i];
	  bif = (long) wi_buf1[i];

	  /*AG55 */

	  temp5 = MULT32X32 (arf, cr_fixed);
	  temp6 = MULT32X32 (aif, ci_fixed);
	  temp7 = MULT32X32 (aif, cr_fixed);
	  temp8 = MULT32X32 (arf, ci_fixed);	/*4 lines added by Kaushik */

	  temp9 = MULT32X32 (brf, cr_fixed);
	  temp10 = MULT32X32 (bif, ci_fixed);
	  temp11 = MULT32X32 (bif, cr_fixed);
	  temp12 = MULT32X32 (brf, ci_fixed);	/*4 lines added by Kaushik */

	  wr_buf1[i] = (long) (temp5 - temp6);
	  wi_buf1[N / 4 + i] = (long) (temp7 + temp8);

	  wr_buf1[N / 4 + i] = (long) (temp9 - temp10);
	  wi_buf1[i] = (long) (temp11 + temp12);
	}
    }
	/***     bswitch == 0 ***/
  else
    {
      /*  Do complex multiply */
      for (i = 0; i < N / 2; i++)
	{
	  arf = (long) wr_buf1[i];
	  aif = (long) wi_buf1[i];
	  cr_fixed = zcos1_fixed[i];
	  ci_fixed = zsin1_fixed[i];

	  /*AG54 */
	  temp9 = MULT32X32 (arf, cr_fixed);
	  temp10 = MULT32X32 (aif, ci_fixed);
	  temp11 = MULT32X32 (aif, cr_fixed);
	  temp12 = MULT32X32 (arf, ci_fixed);

	  wr_buf1[i] = (long) (temp9 - temp10);
	  wi_buf1[i] = (long) (temp11 + temp12);
	}
    }

#ifdef _DB_DOWN_MIX_
  for (i = 0; i < N / 2; i++)
    {

      tcbuf[i] = /*(DSPfract) */ wr_buf1[i];
      tcbuf[N / 2 + i] = /*(DSPfract) */ wi_buf1[i];

    }
#else

  ActChan = chantab[acmod][channum];


  for (i = 0; i < N / 2; i++)
    {
#ifdef GNRNG
      dnmix_buf[ActChan][i] = wr_buf1[i] >> appgainrng;
      dnmix_buf[ActChan][N / 2 + i] = wi_buf1[i] >> appgainrng;

#else
      dnmix_buf[ActChan][i] = wr_buf1[i];
      dnmix_buf[ActChan][N / 2 + i] = wi_buf1[i];
#endif /* GNRNG */
      dnmixbufinu[ActChan] = 1;

    }
#endif /* _DB_DOWN_MIX_ */
//fclose(fp);
}


short bswitch = 0;
long tcbuf[N] = {-373, 85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

long tcbuf_out[N] ={0, 5, 12, 24, 28, 37, 46, 57, 58, 70, 74, 85, 92, 100, 109, 116, 116, 119, 130, 142, 144, 150, 161, 170, 173, 176, 184, 194, 202, 204, 214, 222, 218, 211, 219, 231, 233, 238, 249, 255, 254, 254, 262, 269, 275, 276, 285, 291, 291, 282, 289, 298, 299, 301, 306, 313, 313, 310, 314, 316, 323, 321, 326, 330, 321, 310, 314, 315, 318, 316, 319, 319, 321, 314, 320, 318, 323, 319, 321, 320, 324, 318, 317, 318, 319, 316, 316, 314, 316, 315, 312, 310, 311, 309, 307, 306, 309, 314, 310, 304, 306, 305, 300, 297, 301, 301, 299, 294, 294, 293, 288, 286, 291, 298, 294, 287, 289, 290, 285, 279, 282, 287, 285, 280, 279, 281, 276, 273, -288, -307, -304, -300, -301, -301, -297, -296, -297, -306, -301, -300, -295, -301, -297, -297, -300, -310, -308, -306, -305, -310, -308, -306, -306, -314, -314, -313, -309, -315, -312, -311, -316, -322, -321, -324, -323, -326, -324, -327, -326, -332, -329, -332, -330, -333, -334, -335, -330, -332, -333, -337, -335, -334, -335, -338, -334, -333, -334, -337, -335, -333, -336, -336, -326, -312, -313, -318, -314, -312, -315, -317, -310, -304, -304, -305, -304, -300, -300, -300, -289, -276, -278, -281, -274, -268, -269, -269, -264, -251, -251, -250, -248, -239, -239, -236, -223, -203, -201, -200, -194, -185, -186, -180, -172, -159, -158, -152, -148, -138, -136, -129, -123, -108, -103, -97, -91, -83, -76, -69, -64, -53, -47, -37, -34, -25, -18, -10};

short acmod = 7;
short channum = 5;
int slct = 0;

int main(void)
{
	int i;
	
	puts("itver2 Test Started\n");
	itver2 (bswitch,
			tcbuf,
			acmod,
			channum,
			slct);
	for (i = 0; i < N; i++)
	{
		if (tcbuf[i] != tcbuf_out[i])
		{
			rvex_fail("itver2 Test Failed\n");
			return 1;
		}
	}
	rvex_succeed("itver2 Test Passed\n");
	return 0;
}
