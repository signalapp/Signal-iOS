/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/tone_generate.h - General telephony tone generation.
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
 * $Id: tone_generate.h,v 1.1 2008/11/30 10:17:31 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_TONE_GENERATE_H_)
#define _SPANDSP_PRIVATE_TONE_GENERATE_H_

struct tone_gen_tone_descriptor_s
{
    int32_t phase_rate;
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t gain;
#else
    float gain;
#endif
};

/*!
    Cadenced multi-tone generator descriptor.
*/
struct tone_gen_descriptor_s
{
    tone_gen_tone_descriptor_t tone[4];
    int duration[4];
    int repeat;
};

/*!
    Cadenced multi-tone generator state descriptor. This defines the state of
    a single working instance of a generator.
*/
struct tone_gen_state_s
{
    tone_gen_tone_descriptor_t tone[4];

    uint32_t phase[4];
    int duration[4];
    int repeat;

    int current_section;
    int current_position;
};

#endif
/*- End of file ------------------------------------------------------------*/
