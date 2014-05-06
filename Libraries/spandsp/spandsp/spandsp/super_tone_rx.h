/*
 * SpanDSP - a series of DSP components for telephony
 *
 * super_tone_rx.h - Flexible telephony supervisory tone detection.
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
 * $Id: super_tone_rx.h,v 1.21 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_SUPER_TONE_RX_H_)
#define _SPANDSP_SUPER_TONE_RX_H_

/*! \page super_tone_rx_page Supervisory tone detection

\section super_tone_rx_page_sec_1 What does it do?

The supervisory tone detector may be configured to detect most of the world's
telephone supervisory tones - things like ringback, busy, number unobtainable,
and so on.

\section super_tone_rx_page_sec_2 How does it work?

The supervisory tone detector is passed a series of data structures describing
the tone patterns - the frequencies and cadencing - of the tones to be searched
for. It constructs one or more Goertzel filters to monitor the required tones.
If tones are close in frequency a single Goertzel set to the centre of the
frequency range will be used. This optimises the efficiency of the detector. The
Goertzel filters are applied without applying any special window functional
(i.e. they use a rectangular window), so they have a sinc like response.
However, for most tone patterns their rejection qualities are adequate. 

The detector aims to meet the need of the standard call progress tones, to
ITU-T E.180/Q.35 (busy, dial, ringback, reorder). Also, the extended tones,
to ITU-T E.180, Supplement 2 and EIA/TIA-464-A (recall dial tone, special
ringback tone, intercept tone, call waiting tone, busy verification tone,
executive override tone, confirmation tone).
*/

/*! Tone detection indication callback routine */
typedef void (*tone_report_func_t)(void *user_data, int code, int level, int delay);

typedef struct super_tone_rx_segment_s super_tone_rx_segment_t;

typedef struct super_tone_rx_descriptor_s super_tone_rx_descriptor_t;

typedef struct super_tone_rx_state_s super_tone_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Create a new supervisory tone detector descriptor.
    \param desc The supervisory tone set desciptor. If NULL, the routine will allocate space for a
                descriptor.
    \return The supervisory tone set descriptor.
*/
SPAN_DECLARE(super_tone_rx_descriptor_t *) super_tone_rx_make_descriptor(super_tone_rx_descriptor_t *desc);

/*! Free a supervisory tone detector descriptor.
    \param desc The supervisory tone set desciptor.
    \return 0 for OK, -1 for fail.
*/
SPAN_DECLARE(int) super_tone_rx_free_descriptor(super_tone_rx_descriptor_t *desc);

/*! Add a new tone pattern to a supervisory tone detector set.
    \param desc The supervisory tone set descriptor.
    \return The new tone ID. */
SPAN_DECLARE(int) super_tone_rx_add_tone(super_tone_rx_descriptor_t *desc);

/*! Add a new tone pattern element to a tone pattern in a supervisory tone detector.
    \param desc The supervisory tone set desciptor.
    \param tone The tone ID within the descriptor.
    \param f1 Frequency 1 (-1 for a silent period).
    \param f2 Frequency 2 (-1 for a silent period, or only one frequency).
    \param min The minimum duration, in ms.
    \param max The maximum duration, in ms.
    \return The new number of elements in the tone description.
*/
SPAN_DECLARE(int) super_tone_rx_add_element(super_tone_rx_descriptor_t *desc,
                                            int tone,
                                            int f1,
                                            int f2,
                                            int min,
                                            int max);

/*! Initialise a supervisory tone detector.
    \param s The supervisory tone detector context.
    \param desc The tone descriptor.
    \param callback The callback routine called to report the valid detection or termination of
           one of the monitored tones.
    \param user_data An opaque pointer passed when calling the callback routine.
    \return The supervisory tone detector context.
*/
SPAN_DECLARE(super_tone_rx_state_t *) super_tone_rx_init(super_tone_rx_state_t *s,
                                                         super_tone_rx_descriptor_t *desc,
                                                         tone_report_func_t callback,
                                                         void *user_data);

/*! Release a supervisory tone detector.
    \param s The supervisory tone context.
    \return 0 for OK, -1 for fail.
*/
SPAN_DECLARE(int) super_tone_rx_release(super_tone_rx_state_t *s);

/*! Free a supervisory tone detector.
    \param s The supervisory tone context.
    \return 0 for OK, -1 for fail.
*/
SPAN_DECLARE(int) super_tone_rx_free(super_tone_rx_state_t *s);

/*! Define a callback routine to be called each time a tone pattern element is complete. This is
    mostly used when analysing a tone.
    \param s The supervisory tone context.
    \param callback The callback routine.
*/
SPAN_DECLARE(void) super_tone_rx_segment_callback(super_tone_rx_state_t *s,
                                                  void (*callback)(void *data, int f1, int f2, int duration));

/*! Apply supervisory tone detection processing to a block of audio samples.
    \brief Apply supervisory tone detection processing to a block of audio samples.
    \param super The supervisory tone context.
    \param amp The audio sample buffer.
    \param samples The number of samples in the buffer.
    \return The number of samples processed.
*/
SPAN_DECLARE(int) super_tone_rx(super_tone_rx_state_t *super, const int16_t amp[], int samples);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
