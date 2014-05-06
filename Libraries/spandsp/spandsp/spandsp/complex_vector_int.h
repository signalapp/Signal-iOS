/*
 * SpanDSP - a series of DSP components for telephony
 *
 * complex_vector_int.h
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
 * $Id: complex_vector_int.h,v 1.4 2009/01/31 08:48:11 steveu Exp $
 */

#if !defined(_SPANDSP_COMPLEX_VECTOR_INT_H_)
#define _SPANDSP_COMPLEX_VECTOR_INT_H_

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ void cvec_copyi(complexi_t z[], const complexi_t x[], int n)
{
    memcpy(z, x, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_copyi16(complexi16_t z[], const complexi16_t x[], int n)
{
    memcpy(z, x, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_copyi32(complexi32_t z[], const complexi32_t x[], int n)
{
    memcpy(z, x, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_zeroi(complexi_t z[], int n)
{
    memset(z, 0, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_zeroi16(complexi16_t z[], int n)
{
    memset(z, 0, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_zeroi32(complexi32_t z[], int n)
{
    memset(z, 0, n*sizeof(z[0]));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_seti(complexi_t z[], complexi_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_seti16(complexi16_t z[], complexi16_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/

static __inline__ void cvec_seti32(complexi32_t z[], complexi32_t *x, int n)
{
    int i;
    
    for (i = 0;  i < n;  i++)
        z[i] = *x;
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the dot product of two complex int16_t vectors.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexi32_t) cvec_dot_prodi16(const complexi16_t x[], const complexi16_t y[], int n);

/*! \brief Find the dot product of two complex int32_t vectors.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexi32_t) cvec_dot_prodi32(const complexi32_t x[], const complexi32_t y[], int n);

/*! \brief Find the dot product of two complex int16_t vectors, where the first is a circular buffer
           with an offset for the starting position.
    \param x The first vector.
    \param y The first vector.
    \param n The number of elements in the vectors.
    \param pos The starting position in the x vector.
    \return The dot product of the two vectors. */
SPAN_DECLARE(complexi32_t) cvec_circular_dot_prodi16(const complexi16_t x[], const complexi16_t y[], int n, int pos);

SPAN_DECLARE(void) cvec_lmsi16(const complexi16_t x[], complexi16_t y[], int n, const complexi16_t *error);

SPAN_DECLARE(void) cvec_circular_lmsi16(const complexi16_t x[], complexi16_t y[], int n, int pos, const complexi16_t *error);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
