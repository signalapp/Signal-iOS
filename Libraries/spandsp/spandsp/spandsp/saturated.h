#include <math.h>
/*
 * SpanDSP - a series of DSP components for telephony
 *
 * saturated.h - General saturated arithmetic routines.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001, 2008 Steve Underwood
 *
 * All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License version 2.1,
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * $Id: saturated.h,v 1.4 2009/02/05 12:21:36 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_SATURATED_H_)
#define _SPANDSP_SATURATED_H_

/*! \page saturated_page Saturated arithmetic

\section saturated_page_sec_1 What does it do?


\section saturated_page_sec_2 How does it work?

*/

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ int16_t saturate(int32_t amp)
{
    int16_t amp16;

    /* Hopefully this is optimised for the common case - not clipping */
    amp16 = (int16_t) amp;
    if (amp == amp16)
        return amp16;
    if (amp > INT16_MAX)
        return INT16_MAX;
    return INT16_MIN;
}
/*- End of function --------------------------------------------------------*/

/*! Saturate to 15 bits, rather than the usual 16 bits. This is often a useful function. */
static __inline__ int16_t saturate15(int32_t amp)
{
    if (amp > 16383)
        return 16383;
    if (amp < -16384)
        return -16384;
    return (int16_t) amp;
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t fsaturatef(float famp)
{
    if (famp > (float) INT16_MAX)
        return INT16_MAX;
    if (famp < (float) INT16_MIN)
        return INT16_MIN;
    return (int16_t) lrintf(famp);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t fsaturate(double damp)
{
    if (damp > (double) INT16_MAX)
        return INT16_MAX;
    if (damp < (double) INT16_MIN)
        return INT16_MIN;
    return (int16_t) lrint(damp);
}
/*- End of function --------------------------------------------------------*/

/* Saturate to a 16 bit integer, using the fastest float to int conversion */
static __inline__ int16_t ffastsaturatef(float famp)
{
    if (famp > (float) INT16_MAX)
        return INT16_MAX;
    if (famp < (float) INT16_MIN)
        return INT16_MIN;
    return (int16_t) lfastrintf(famp);
}
/*- End of function --------------------------------------------------------*/

/* Saturate to a 16 bit integer, using the fastest double to int conversion */
static __inline__ int16_t ffastsaturate(double damp)
{
    if (damp > (double) INT16_MAX)
        return INT16_MAX;
    if (damp < (double) INT16_MIN)
        return INT16_MIN;
    return (int16_t) lfastrint(damp);
}
/*- End of function --------------------------------------------------------*/

/* Saturate to a 16 bit integer, using the closest float to int conversion */
static __inline__ float ffsaturatef(float famp)
{
    if (famp > (float) INT16_MAX)
        return (float) INT16_MAX;
    if (famp < (float) INT16_MIN)
        return (float) INT16_MIN;
    return famp;
}
/*- End of function --------------------------------------------------------*/

/* Saturate to a 16 bit integer, using the closest double to int conversion */
static __inline__ double ffsaturate(double famp)
{
    if (famp > (double) INT16_MAX)
        return (double) INT16_MAX;
    if (famp < (double) INT16_MIN)
        return (double) INT16_MIN;
    return famp;
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t saturated_add16(int16_t a, int16_t b)
{
#if defined(__GNUC__)  &&  defined(__i386__)
    __asm__ __volatile__(
        " addw %2,%0;\n"
        " jno 0f;\n"
        " movw $0x7fff,%0;\n"
        " adcw $0,%0;\n"
        "0:"
        : "=r" (a)
        : "0" (a), "ir" (b)
        : "cc"
    );
    return a;
#else
    return saturate((int32_t) a + (int32_t) b);
#endif
}
/*- End of function --------------------------------------------------------*/

static __inline__ int32_t saturated_add32(int32_t a, int32_t b)
{
#if defined(__GNUC__)  &&  defined(__i386__)
    __asm__ __volatile__(
        " addl %2,%0;\n"
        " jno 0f;\n"
        " movl $0x7fffffff,%0;\n"
        " adcl $0,%0;\n"
        "0:"
        : "=r" (a)
        : "0" (a), "ir" (b)
        : "cc"
    );
    return a;
#else
    uint32_t A;

    if (a < 0)
    {
        if (b >= 0)
            return  a + b;
        /*endif*/
        A = (uint32_t) -(a + 1) + (uint32_t) -(b + 1);
        return (A >= INT32_MAX)  ?  INT32_MIN  :  -(int32_t) A - 2;
    }
    /*endif*/
    if (b <= 0)
        return  a + b;
    /*endif*/
    A = (uint32_t) a + (uint32_t) b;
    return (A > INT32_MAX)  ?  INT32_MAX  :  A;
#endif
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t saturated_sub16(int16_t a, int16_t b)
{
    return saturate((int32_t) a - (int32_t) b);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t saturated_mul16(int16_t a, int16_t b)
{
    if (a == INT16_MIN  &&  b == INT16_MIN)
        return INT16_MAX;
    /*endif*/
    return (int16_t) (((int32_t) a*(int32_t) b) >> 15);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int32_t saturated_mul_16_32(int16_t a, int16_t b)
{
    return ((int32_t) a*(int32_t) b) << 1;
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t saturated_abs16(int16_t a)
{
    return (a == INT16_MIN)  ?  INT16_MAX  :  (int16_t) abs(a);
}
/*- End of function --------------------------------------------------------*/

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
