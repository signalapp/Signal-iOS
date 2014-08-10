/*
 * SpanDSP - a series of DSP components for telephony
 *
 * floating_fudge.h - A bunch of shims, to use double maths
 *                    functions on platforms which lack the
 *                    float versions with an 'f' at the end,
 *                    and to deal with the vaguaries of lrint().
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2008 Steve Underwood
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
 */

#if !defined(_FLOATING_FUDGE_H_)
#define _FLOATING_FUDGE_H_

#if defined(__cplusplus)
extern "C"
{
#endif

#if !defined(HAVE_SINF)
static __inline__ float sinf(float x)
{
	return (float) sin((double) x);
}
#endif

#if !defined(HAVE_COSF)
static __inline__ float cosf(float x)
{
	return (float) cos((double) x);
}
#endif

#if !defined(HAVE_TANF)
static __inline__ float tanf(float x)
{
	return (float) tan((double) x);
}
#endif

#if !defined(HAVE_ASINF)
static __inline__ float asinf(float x)
{
	return (float) asin((double) x);
}
#endif

#if !defined(HAVE_ACOSF)
static __inline__ float acosf(float x)
{
	return (float) acos((double) x);
}
#endif

#if !defined(HAVE_ATANF)
static __inline__ float atanf(float x)
{
	return (float) atan((double) x);
}

#endif

#if !defined(HAVE_ATAN2F)
static __inline__ float atan2f(float y, float x)
{
	return (float) atan2((double) y, (double) x);
}

#endif

#if !defined(HAVE_CEILF)
static __inline__ float ceilf(float x)
{
	return (float) ceil((double) x);
}
#endif

#if !defined(HAVE_FLOORF)
static __inline__ float floorf(float x)
{
	return (float) floor((double) x);
}

#endif

#if !defined(HAVE_POWF)
static __inline__ float powf(float x, float y)
{
    return (float) pow((double) x, (double) y);
}
#endif

#if !defined(HAVE_EXPF)
static __inline__ float expf(float x)
{
    return (float) expf((double) x);
}
#endif

#if !defined(HAVE_LOGF)
static __inline__ float logf(float x)
{
	return (float) logf((double) x);
}
#endif

#if !defined(HAVE_LOG10F)
static __inline__ float log10f(float x)
{
    return (float) log10((double) x);
}
#endif

#if defined(__cplusplus)
}
#endif

#endif

/*- End of file ------------------------------------------------------------*/
