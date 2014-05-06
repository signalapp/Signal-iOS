/*
 * SpanDSP - a series of DSP components for telephony
 *
 * arctan2.h - A quick rough approximate arc tan
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
 * $Id: arctan2.h,v 1.13 2008/05/29 13:04:19 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_ARCTAN2_H_)
#define _SPANDSP_ARCTAN2_H_

/*! \page arctan2_page Fast approximate four quadrant arc-tangent
\section arctan2_page_sec_1 What does it do?
This module provides a fast approximate 4-quadrant arc tangent function,
based on something at dspguru.com. The worst case error is about 4.07 degrees.
This is fine for many "where am I" type evaluations in comms. work.

\section arctan2_page_sec_2 How does it work?
???.
*/

#if defined(__cplusplus)
extern "C"
{
#endif

/* This returns its answer as a signed 32 bit integer phase value. */
static __inline__ int32_t arctan2(float y, float x)
{
    float abs_y;
    float angle;

    if (x == 0.0f  ||  y == 0.0f)
        return 0;
    
    abs_y = fabsf(y);

    /* If we are in quadrant II or III, flip things around */
    if (x < 0.0f)
        angle = 3.0f - (x + abs_y)/(abs_y - x);
    else
        angle = 1.0f - (x - abs_y)/(abs_y + x);
    angle *= 536870912.0f;

    /* If we are in quadrant III or IV, negate to return an
       answer in the range +-pi */
    if (y < 0.0f)
        angle = -angle;
    return (int32_t) angle;
}
/*- End of function --------------------------------------------------------*/

#if 0
/* This returns its answer in radians, in the range +-pi. */
static __inline__ float arctan2f(float y, float x)
{
    float angle;
    float fx;
    float fy;

    if (x == 0.0f  ||  y == 0.0f)
        return 0;
    fx = fabsf(x);
    fy = fabsf(y);
    /* Deal with the octants */
    /* N.B. 0.28125 == (1/4 + 1/32) */
    if (fy > fx)
        angle = 3.1415926f/2.0f - fx*fy/(y*y + 0.28125f*x*x);
    else
        angle = fy*fx/(x*x + 0.28125f*y*y);
    
    /* Deal with the quadrants, to bring the final answer to the range +-pi */
    if (x < 0.0f)
        angle = 3.1415926f - angle;
    if (y < 0.0f)
        angle = -angle;
    return angle;
}
/*- End of function --------------------------------------------------------*/
#endif

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
