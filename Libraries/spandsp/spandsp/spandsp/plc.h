/*
 * SpanDSP - a series of DSP components for telephony
 *
 * plc.h
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
 * $Id: plc.h,v 1.21 2009/02/10 13:06:47 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PLC_H_)
#define _SPANDSP_PLC_H_

/*! \page plc_page Packet loss concealment
\section plc_page_sec_1 What does it do?
The packet loss concealment module provides a synthetic fill-in signal, to minimise
the audible effect of lost packets in VoIP applications. It is not tied to any
particular codec, and could be used with almost any codec which does not
specify its own procedure for packet loss concealment.

Where a codec specific concealment procedure exists, that algorithm is usually built
around knowledge of the characteristics of the particular codec. It will, therefore,
generally give better results for that particular codec than this generic concealer will.

The PLC code implements an algorithm similar to the one described in Appendix 1 of G.711.
However, the G.711 algorithm is optimised for 10ms packets. Few people use such small
packets. 20ms is a much more common value, and longer packets are also quite common. The
algorithm has been adjusted with this in mind. Also, the G.711 approach causes an
algorithmic delay, and requires significant buffer manipulation when there is no packet
loss. The algorithm used here avoids this. It causes no delay, and achieves comparable
quality with normal speech.

Note that both this algorithm, and the one in G.711 are optimised for speech. For most kinds
of music a much slower decay on bursts of lost packets give better results.

\section plc_page_sec_2 How does it work?
While good packets are being received, the plc_rx() routine keeps a record of the trailing
section of the known speech signal. If a packet is missed, plc_fillin() is called to produce
a synthetic replacement for the real speech signal. The average mean difference function
(AMDF) is applied to the last known good signal, to determine its effective pitch.
Based on this, the last pitch period of signal is saved. Essentially, this cycle of speech
will be repeated over and over until the real speech resumes. However, several refinements
are needed to obtain smooth pleasant sounding results.

- The two ends of the stored cycle of speech will not always fit together smoothly. This can
  cause roughness, or even clicks, at the joins between cycles. To soften this, the
  1/4 pitch period of real speech preceeding the cycle to be repeated is blended with the last
  1/4 pitch period of the cycle to be repeated, using an overlap-add (OLA) technique (i.e.
  in total, the last 5/4 pitch periods of real speech are used).

- The start of the synthetic speech will not always fit together smoothly with the tail of
  real speech passed on before the erasure was identified. Ideally, we would like to modify
  the last 1/4 pitch period of the real speech, to blend it into the synthetic speech. However,
  it is too late for that. We could have delayed the real speech a little, but that would
  require more buffer manipulation, and hurt the efficiency of the no-lost-packets case
  (which we hope is the dominant case). Instead we use a degenerate form of OLA to modify
  the start of the synthetic data. The last 1/4 pitch period of real speech is time reversed,
  and OLA is used to blend it with the first 1/4 pitch period of synthetic speech. The result
  seems quite acceptable.

- As we progress into the erasure, the chances of the synthetic signal being anything like
  correct steadily fall. Therefore, the volume of the synthesized signal is made to decay
  linearly, such that after 50ms of missing audio it is reduced to silence.

- When real speech resumes, an extra 1/4 pitch period of synthetic speech is blended with the
  start of the real speech. If the erasure is small, this smoothes the transition. If the erasure
  is long, and the synthetic signal has faded to zero, the blending softens the start up of the
  real signal, avoiding a kind of "click" or "pop" effect that might occur with a sudden onset.

\section plc_page_sec_3 How do I use it?
Before audio is processed, call plc_init() to create an instance of the packet loss
concealer. For each received audio packet that is acceptable (i.e. not including those being
dropped for being too late) call plc_rx() to record the content of the packet. Note this may
modify the packet a little after a period of packet loss, to blend real synthetic data smoothly.
When a real packet is not available in time, call plc_fillin() to create a sythetic substitute.
That's it!
*/

/*! Minimum allowed pitch (66 Hz) */
#define PLC_PITCH_MIN           120
/*! Maximum allowed pitch (200 Hz) */
#define PLC_PITCH_MAX           40
/*! Maximum pitch OLA window */
#define PLC_PITCH_OVERLAP_MAX   (PLC_PITCH_MIN >> 2)
/*! The length over which the AMDF function looks for similarity (20 ms) */
#define CORRELATION_SPAN        160
/*! History buffer length. The buffer much also be at leat 1.25 times
    PLC_PITCH_MIN, but that is much smaller than the buffer needs to be for
    the pitch assessment. */
#define PLC_HISTORY_LEN         (CORRELATION_SPAN + PLC_PITCH_MIN)

/*!
    The generic packet loss concealer context.
*/
typedef struct
{
    /*! Consecutive erased samples */
    int missing_samples;
    /*! Current offset into pitch period */
    int pitch_offset;
    /*! Pitch estimate */
    int pitch;
    /*! Buffer for a cycle of speech */
    float pitchbuf[PLC_PITCH_MIN];
    /*! History buffer */
    int16_t history[PLC_HISTORY_LEN];
    /*! Current pointer into the history buffer */
    int buf_ptr;
} plc_state_t;


#if defined(__cplusplus)
extern "C"
{
#endif

/*! Process a block of received audio samples for PLC.
    \brief Process a block of received audio samples for PLC.
    \param s The packet loss concealer context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples in the buffer. */
SPAN_DECLARE(int) plc_rx(plc_state_t *s, int16_t amp[], int len);

/*! Fill-in a block of missing audio samples.
    \brief Fill-in a block of missing audio samples.
    \param s The packet loss concealer context.
    \param amp The audio sample buffer.
    \param len The number of samples to be synthesised.
    \return The number of samples synthesized. */
SPAN_DECLARE(int) plc_fillin(plc_state_t *s, int16_t amp[], int len);

/*! Initialise a packet loss concealer context.
    \brief Initialise a PLC context.
    \param s The packet loss concealer context.
    \return A pointer to the the packet loss concealer context. */
SPAN_DECLARE(plc_state_t *) plc_init(plc_state_t *s);

/*! Release a packet loss concealer context.
    \param s The packet loss concealer context.
    \return 0 for OK. */
SPAN_DECLARE(int) plc_release(plc_state_t *s);

/*! Free a packet loss concealer context.
    \param s The packet loss concealer context.
    \return 0 for OK. */
SPAN_DECLARE(int) plc_free(plc_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
