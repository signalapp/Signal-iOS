/*
 * SpanDSP - a series of DSP components for telephony
 *
 * complex_vector_float.h
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
 * $Id: complex_vector_float.h,v 1.13 2009/02/04 13:18:53 steveu Exp $
 */

#if !defined(_SPANDSP_COMPLEX_VECTOR_FLOAT_H_)
#define _SPANDSP_COMPLEX_VECTOR_FLOAT_H_

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ void cvec_copyf(complexf_t z[], const complexf_t x[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = x[i];
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_copy(complex_t z[], const complex_t x[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = x[i];
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ void cvec_copyl(complexl_t z[], const complexl_t x[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = x[i];
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ void cvec_zerof(complexf_t z[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = complex_setf(0.0f, 0.0f);
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_zero(complex_t z[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = complex_set(0.0, 0.0);
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ void cvec_zerol(complexl_t z[], int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = complex_setl(0.0, 0.0);
}
/*- End of function --------------------------------------------------------*/
#endif

static __inline__ void cvec_setf(complexf_t z[], complexf_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_set(complex_t z[], complex_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/

#if defined(HAVE_LONG_DOUBLE)
static __inline__ void cvec_setl(complexl_t z[], complexl_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/
#endif

SPAN_DECLARE(void) cvec_mulf(complexf_t z[], const complexf_t x[], const complexf_t y[], int n);

SPAN_DECLARE(void) cvec_mul(complex_t z[], const complex_t x[], const complex_t y[], int n);

#if defined(HAVE_LONG_DOUBLE)
SPAN_DECLARE(void) cvec_mull(complexl_t z[], const complexl_t x[], const complexl_t y[], int n);
#endif

/*! \brief Find the dot product of two complex float vectors.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexf_t) cvec_dot_prodf(const complexf_t x[], const complexf_t y[], int n);

/*! \brief Find the dot product of two complex double vectors.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complex_t) cvec_dot_prod(const complex_t x[], const complex_t y[], int n);

#if defined(HAVE_LONG_DOUBLE)
/*! \brief Find the dot product of two complex long double vectors.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexl_t) cvec_dot_prodl(const complexl_t x[], const complexl_t y[], int n);
#endif

/*! \brief Find the dot product of two complex float vectors, where the first is a circular buffer
           with an offset for the starting position.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \param pos The starting position in the x vector.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexf_t) cvec_circular_dot_prodf(const complexf_t x[], const complexf_t y[], int n, int pos);

SPAN_DECLARE(void) cvec_lmsf(const complexf_t x[], complexf_t y[], int n, const complexf_t *error);

SPAN_DECLARE(void) cvec_circular_lmsf(const complexf_t x[], complexf_t y[], int n, int pos, const complexf_t *error);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
