/*
 * SpanDSP - a series of DSP components for telephony
 *
 * biquad.h - General telephony bi-quad section routines (currently this just
 *            handles canonic/type 2 form)
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001 Steve Underwood
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
 * $Id: biquad.h,v 1.14 2008/04/17 14:26:59 steveu Exp $
 */

/*! \page biquad_page Bi-quadratic filter sections
\section biquad_page_sec_1 What does it do?
???.

\section biquad_page_sec_2 How does it work?
???.
*/

#if !defined(_SPANDSP_BIQUAD_H_)
#define _SPANDSP_BIQUAD_H_

typedef struct
{
    int32_t gain;
    int32_t a1;
    int32_t a2;
    int32_t b1;
    int32_t b2;

    int32_t z1;
    int32_t z2;

#if FIRST_ORDER_NOISE_SHAPING
    int32_t residue;
#elif SECOND_ORDER_NOISE_SHAPING
    int32_t residue1;
    int32_t residue2;
#endif
} biquad2_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ void biquad2_init(biquad2_state_t *bq,
                                    int32_t gain,
                                    int32_t a1,
                                    int32_t a2,
                                    int32_t b1,
                                    int32_t b2)
{
    bq->gain = gain;
    bq->a1 = a1;
    bq->a2 = a2;
    bq->b1 = b1;
    bq->b2 = b2;
    
    bq->z1 = 0;
    bq->z2 = 0;    

#if FIRST_ORDER_NOISE_SHAPING
    bq->residue = 0;
#elif SECOND_ORDER_NOISE_SHAPING
    bq->residue1 = 0;
    bq->residue2 = 0;
#endif
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t biquad2(biquad2_state_t *bq, int16_t sample)
{
    int32_t y;
    int32_t z0;
    
    z0 = sample*bq->gain + bq->z1*bq->a1 + bq->z2*bq->a2;
    y = z0 + bq->z1*bq->b1 + bq->z2*bq->b2;

    bq->z2 = bq->z1;
    bq->z1 = z0 >> 15;
#if FIRST_ORDER_NOISE_SHAPING
    y += bq->residue; 
    bq->residue = y & 0x7FFF;
#elif SECOND_ORDER_NOISE_SHAPING
    y += (2*bq->residue1 - bq->residue2);
    bq->residue2 = bq->residue1;
    bq->residue1 = y & 0x7FFF;
#endif
    y >>= 15;
    return (int16_t) y;
}
/*- End of function --------------------------------------------------------*/

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
