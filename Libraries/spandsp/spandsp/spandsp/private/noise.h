/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/noise.h - A low complexity audio noise generator, suitable for
 *                   real time generation (current just approx AWGN)
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005 Steve Underwood
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
 * $Id: noise.h,v 1.1 2008/11/30 12:45:09 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_NOISE_H_)
#define _SPANDSP_PRIVATE_NOISE_H_

/*!
    Noise generator descriptor. This contains all the state information for an instance
    of the noise generator.
 */
struct noise_state_s
{
    int class_of_noise;
    int quality;
    int32_t rms;
    uint32_t rndnum;
    int32_t state;
};

#endif
/*- End of file ------------------------------------------------------------*/
