/*
 * SpanDSP - a series of DSP components for telephony
 *
 * dc_restore.h - General telephony routines to restore the zero D.C.
 *                level to audio which has a D.C. bias.
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
 * $Id: dc_restore.h,v 1.24 2008/09/19 14:02:05 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_DC_RESTORE_H_)
#define _SPANDSP_DC_RESTORE_H_

/*! \page dc_restore_page Removing DC bias from a signal

\section dc_restore_page_sec_1 What does it do?

Telecoms signals often contain considerable DC, but DC upsets a lot of signal
processing functions. Placing a zero DC restorer at the front of the processing
chain can often simplify the downstream processing. 

\section dc_restore_page_sec_2 How does it work?

The DC restorer uses a leaky integrator to provide a long-ish term estimate of
the DC bias in the signal. A 32 bit estimate is used for the 16 bit audio, so
the noise introduced by the estimation can be keep in the lower bits, and the 16
bit DC value, which is subtracted from the signal, is fairly clean. The
following code fragment shows the algorithm used. dc_bias is a 32 bit integer,
while the sample and the resulting clean_sample are 16 bit integers. 

    dc_bias += ((((int32_t) sample << 15) - dc_bias) >> 14);
    clean_sample = sample - (dc_bias >> 15); 
*/

/*!
    Zero DC restoration descriptor. This defines the working state for a single
    instance of DC content filter.
*/
typedef struct
{
    int32_t state;
} dc_restore_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ void dc_restore_init(dc_restore_state_t *dc)
{
    dc->state = 0;
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t dc_restore(dc_restore_state_t *dc, int16_t sample)
{
    dc->state += ((((int32_t) sample << 15) - dc->state) >> 14);
    return (int16_t) (sample - (dc->state >> 15));
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t dc_restore_estimate(dc_restore_state_t *dc)
{
    return (int16_t) (dc->state >> 15);
}
/*- End of function --------------------------------------------------------*/

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
