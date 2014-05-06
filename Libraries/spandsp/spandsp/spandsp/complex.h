/*
 * SpanDSP - a series of DSP components for telephony
 *
 * complex.h
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2003 Steve Underwood
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
 * $Id: complex.h,v 1.20 2009/02/21 05:39:08 steveu Exp $
 */

/*! \file */

/*! \page complex_page Complex number support
\section complex_page_sec_1 What does it do?
Complex number support is part of the C99 standard. However, support for this
in C compilers is still patchy. A set of complex number feaures is provided as
a "temporary" measure, until native C language complex number support is
widespread.
*/

#if !defined(_SPANDSP_COMPLEX_H_)
#define _SPANDSP_COMPLEX_H_

/*!
    Floating complex type.
*/
typedef struct
{
    /*! \brief Real part. */
    float re;
    /*! \brief Imaginary part. */
    float im;
} complexf_t;

/*!
    Floating complex type.
*/
typedef struct
{
    /*! \brief Real part. */
    double re;
    /*! \brief Imaginary part. */
    double im;
} complex_t;

#if defined(HAVE_LONG_DOUBLE)
/*!
    Long double complex type.
*/
typedef struct
{
    /*! \brief Real part. */
    long double re;
    /*! \brief Imaginary part. */
    long double im;
} complexl_t;
#endif

/*!
    Complex integer type.
*/
typedef struct
{
    /*! \brief Real part. */
    int re;
    /*! \brief Imaginary part. */
    int im;
} complexi_t;

/*!
    Complex 16 bit integer type.
*/
typedef struct
{
    /*! \brief Real part. */
    int16_t re;
    /*! \brief Imaginary part. */
    int16_t im;
} complexi16_t;

/*!
    Complex 32 bit integer type.
*/
typedef struct
{
    /*! \brief Real part. */
    int32_t re;
    /*! \brief Imaginary part. */
    int32_t im;
} complexi32_t;

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ complexf_t complex_setf(float re, float im)
{
    complexf_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_set(double re, double im)
{
    complex_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_setl(long double re, long double im)
{
    complexl_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexi_t complex_seti(int re, int im)
{
    complexi_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_seti16(int16_t re, int16_t im)
{
    complexi16_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_seti32(int32_t re, int32_t im)
{
    complexi32_t z;

    z.re = re;
    z.im = im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexf_t complex_addf(const complexf_t *x, const complexf_t *y)
{
    complexf_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_add(const complex_t *x, const complex_t *y)
{
    complex_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_addl(const complexl_t *x, const complexl_t *y)
{
    complexl_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexi_t complex_addi(const complexi_t *x, const complexi_t *y)
{
    complexi_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_addi16(const complexi16_t *x, const complexi16_t *y)
{
    complexi16_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_addi32(const complexi32_t *x, const complexi32_t *y)
{
    complexi32_t z;

    z.re = x->re + y->re;
    z.im = x->im + y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexf_t complex_subf(const complexf_t *x, const complexf_t *y)
{
    complexf_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_sub(const complex_t *x, const complex_t *y)
{
    complex_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_subl(const complexl_t *x, const complexl_t *y)
{
    complexl_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexi_t complex_subi(const complexi_t *x, const complexi_t *y)
{
    complexi_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_subi16(const complexi16_t *x, const complexi16_t *y)
{
    complexi16_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_subi32(const complexi32_t *x, const complexi32_t *y)
{
    complexi32_t z;

    z.re = x->re - y->re;
    z.im = x->im - y->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexf_t complex_mulf(const complexf_t *x, const complexf_t *y)
{
    complexf_t z;

    z.re = x->re*y->re - x->im*y->im;
    z.im = x->re*y->im + x->im*y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_mul(const complex_t *x, const complex_t *y)
{
    complex_t z;

    z.re = x->re*y->re - x->im*y->im;
    z.im = x->re*y->im + x->im*y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_mull(const complexl_t *x, const complexl_t *y)
{
    complexl_t z;

    z.re = x->re*y->re - x->im*y->im;
    z.im = x->re*y->im + x->im*y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexi_t complex_muli(const complexi_t *x, const complexi_t *y)
{
    complexi_t z;

    z.re = x->re*y->re - x->im*y->im;
    z.im = x->re*y->im + x->im*y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_muli16(const complexi16_t *x, const complexi16_t *y)
{
    complexi16_t z;

    z.re = (int16_t) ((int32_t) x->re*(int32_t) y->re - (int32_t) x->im*(int32_t) y->im);
    z.im = (int16_t) ((int32_t) x->re*(int32_t) y->im + (int32_t) x->im*(int32_t) y->re);
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_mul_q1_15(const complexi16_t *x, const complexi16_t *y)
{
    complexi16_t z;

    z.re = (int16_t) (((int32_t) x->re*(int32_t) y->re - (int32_t) x->im*(int32_t) y->im) >> 15);
    z.im = (int16_t) (((int32_t) x->re*(int32_t) y->im + (int32_t) x->im*(int32_t) y->re) >> 15);
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_muli32i16(const complexi32_t *x, const complexi16_t *y)
{
    complexi32_t z;

    z.re = x->re*(int32_t) y->re - x->im*(int32_t) y->im;
    z.im = x->re*(int32_t) y->im + x->im*(int32_t) y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_muli32(const complexi32_t *x, const complexi32_t *y)
{
    complexi32_t z;

    z.re = x->re*y->re - x->im*y->im;
    z.im = x->re*y->im + x->im*y->re;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexf_t complex_divf(const complexf_t *x, const complexf_t *y)
{
    complexf_t z;
    float f;
    
    f = y->re*y->re + y->im*y->im;
    z.re = ( x->re*y->re + x->im*y->im)/f;
    z.im = (-x->re*y->im + x->im*y->re)/f;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_div(const complex_t *x, const complex_t *y)
{
    complex_t z;
    double f;
    
    f = y->re*y->re + y->im*y->im;
    z.re = ( x->re*y->re + x->im*y->im)/f;
    z.im = (-x->re*y->im + x->im*y->re)/f;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_divl(const complexl_t *x, const complexl_t *y)
{
    complexl_t z;
    long double f;
    
    f = y->re*y->re + y->im*y->im;
    z.re = ( x->re*y->re + x->im*y->im)/f;
    z.im = (-x->re*y->im + x->im*y->re)/f;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexf_t complex_conjf(const complexf_t *x)
{
    complexf_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complex_t complex_conj(const complex_t *x)
{
    complex_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ complexl_t complex_conjl(const complexl_t *x)
{
    complexl_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ complexi_t complex_conji(const complexi_t *x)
{
    complexi_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi16_t complex_conji16(const complexi16_t *x)
{
    complexi16_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ complexi32_t complex_conji32(const complexi32_t *x)
{
    complexi32_t z;

    z.re = x->re;
    z.im = -x->im;
    return z;
}
/*- End of function --------------------------------------------------------*/

static __inline__ float powerf(const complexf_t *x)
{
    return x->re*x->re + x->im*x->im;
}
/*- End of function --------------------------------------------------------*/

static __inline__ double power(const complex_t *x)
{
    return x->re*x->re + x->im*x->im;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ long double powerl(const complexl_t *x)
{
    return x->re*x->re + x->im*x->im;
}
/*- End of function --------------------------------------------------------*/
#endif

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
