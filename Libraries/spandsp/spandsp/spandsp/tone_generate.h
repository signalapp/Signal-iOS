/*
 * SpanDSP - a series of DSP components for telephony
 *
 * tone_generate.h - General telephony tone generation.
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
 * $Id: tone_generate.h,v 1.39 2009/06/02 16:03:56 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_TONE_GENERATE_H_)
#define _SPANDSP_TONE_GENERATE_H_

/*! \page tone_generation_page Tone generation
\section tone_generation_page_sec_1 What does it do?
The tone generation module provides for the generation of cadenced tones,
suitable for a wide range of telephony applications. 

\section tone_generation_page_sec_2 How does it work?
Oscillators are a problem. They oscillate due to instability, and yet we need
them to behave in a stable manner. A look around the web will reveal many papers
on this subject. Many describe rather complex solutions to the problem. However,
we are only concerned with telephony applications. It is possible to generate
the tones we need with a very simple efficient scheme. It is also practical to
use an exhaustive test to prove the oscillator is stable under all the
conditions in which we will use it. 
*/

typedef struct tone_gen_tone_descriptor_s tone_gen_tone_descriptor_t;

/*!
    Cadenced multi-tone generator descriptor.
*/
typedef struct tone_gen_descriptor_s tone_gen_descriptor_t;

/*!
    Cadenced multi-tone generator state descriptor. This defines the state of
    a single working instance of a generator.
*/
typedef struct tone_gen_state_s tone_gen_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Create a tone generator descriptor
    \brief Create a tone generator descriptor
    \param s The descriptor
    \param f1 The first frequency, in Hz
    \param l1 The level of the first frequency, in dBm0
    \param f2 0 for no second frequency, a positive number for the second frequency,
           in Hz, or a negative number for an AM modulation frequency, in Hz
    \param l2 The level of the second frequency, in dBm0, or the percentage modulation depth
           for an AM modulated tone.
    \param d1 x
    \param d2 x
    \param d3 x
    \param d4 x
    \param repeat x */
SPAN_DECLARE(void) make_tone_gen_descriptor(tone_gen_descriptor_t *s,
                                            int f1,
                                            int l1,
                                            int f2,
                                            int l2,
                                            int d1,
                                            int d2,
                                            int d3,
                                            int d4,
                                            int repeat);

SPAN_DECLARE_NONSTD(int) tone_gen(tone_gen_state_t *s, int16_t amp[], int max_samples);

SPAN_DECLARE(tone_gen_state_t *) tone_gen_init(tone_gen_state_t *s, tone_gen_descriptor_t *t);

SPAN_DECLARE(int) tone_gen_release(tone_gen_state_t *s);

SPAN_DECLARE(int) tone_gen_free(tone_gen_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
