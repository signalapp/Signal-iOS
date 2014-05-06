/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/time_scale.h - Time scaling for linear speech data
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004 Steve Underwood
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
 * $Id: time_scale.h,v 1.1 2008/11/15 14:27:29 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_TIME_SCALE_H_)
#define _SPANDSP_PRIVATE_TIME_SCALE_H_

#define TIME_SCALE_MAX_SAMPLE_RATE  48000
#define TIME_SCALE_MIN_PITCH        60
#define TIME_SCALE_MAX_PITCH        250
#define TIME_SCALE_BUF_LEN          (2*TIME_SCALE_MAX_SAMPLE_RATE/TIME_SCALE_MIN_PITCH)

/*! Audio time scaling descriptor. */
struct time_scale_state_s
{
    int sample_rate;
    int min_pitch;
    int max_pitch;
    int buf_len;
    float playout_rate;
    double rcomp;
    double rate_nudge;
    int fill;
    int lcp;
    int16_t buf[TIME_SCALE_BUF_LEN];
};

#endif
/*- End of file ------------------------------------------------------------*/
