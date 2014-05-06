/*
 * SpanDSP - a series of DSP components for telephony
 *
 * time_scale.h - Time scaling for linear speech data
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
 * $Id: time_scale.h,v 1.20 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_TIME_SCALE_H_)
#define _SPANDSP_TIME_SCALE_H_

#include "telephony.h"
#include "private/time_scale.h"

/*! \page time_scale_page Time scaling speech
\section time_scale_page_sec_1 What does it do?
The time scaling module allows speech files to be played back at a
different speed from the speed at which they were recorded. If this
were done by simply speeding up or slowing down replay, the pitch of
the voice would change, and sound very odd. This module keeps the pitch
of the voice at its original level.

The speed of the voice may be altered over a wide range. However, the practical
useful rates are between about half normal speed and twice normal speed.

\section time_scale_page_sec_2 How does it work?
The time scaling module is based on the Pointer Interval Controlled
OverLap and Add (PICOLA) method, developed by Morita Naotaka.
Mikio Ikeda has an excellent web page on this subject at
http://keizai.yokkaichi-u.ac.jp/~ikeda/research/picola.html
There is also working code there. This implementation uses
exactly the same algorithms, but the code is a complete rewrite.
Mikio's code batch processes files. This version works incrementally
on streams, and allows multiple streams to be processed concurrently.

\section time_scale_page_sec_3 How do I used it?
The output buffer must be big enough to hold the maximum number of samples which
could result from the data in the input buffer, which is:

    input_len*playout_rate + sample_rate/TIME_SCALE_MIN_PITCH + 1
*/

/*! Audio time scaling descriptor. */
typedef struct time_scale_state_s time_scale_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a time scale context. This must be called before the first
    use of the context, to initialise its contents.
    \brief Initialise a time scale context.
    \param s The time scale context.
    \param sample_rate The sample rate of the signal.
    \param playout_rate The ratio between the output speed and the input speed.
    \return A pointer to the context, or NULL if there was a problem. */
SPAN_DECLARE(time_scale_state_t *) time_scale_init(time_scale_state_t *s, int sample_rate, float playout_rate);

/*! \brief Release a time scale context.
    \param s The time scale context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) time_scale_release(time_scale_state_t *s);

/*! \brief Free a time scale context.
    \param s The time scale context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) time_scale_free(time_scale_state_t *s);

/*! Change the time scale rate.
    \brief Change the time scale rate.
    \param s The time scale context.
    \param playout_rate The ratio between the output speed and the input speed.
    \return 0 if changed OK, else -1. */
SPAN_DECLARE(int) time_scale_rate(time_scale_state_t *s, float playout_rate);

/*! Find the maximum possible samples which could result from scaling the specified
    number of input samples, at the current playback rate.
    \brief Find the maximum possible output samples.
    \param s The time scale context.
    \param input_len The number of input samples.
    \return The maximum possible output samples. */
SPAN_DECLARE(int) time_scale_max_output_len(time_scale_state_t *s, int input_len);

/*! Time scale a chunk of audio samples.
    \brief Time scale a chunk of audio samples.
    \param s The time scale context.
    \param out The output audio sample buffer. This must be large enough to accept
           the longest possible result from processing the input data. See the
           algorithm documentation for how the longest possible result may be calculated.
    \param in The input audio sample buffer.
    \param len The number of input samples.
    \return The number of output samples.
*/
SPAN_DECLARE(int) time_scale(time_scale_state_t *s, int16_t out[], int16_t in[], int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
