/*
 * SpanDSP - a series of DSP components for telephony
 *
 * g722.h - The ITU G.722 codec.
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
 * Based on a single channel G.722 codec which is:
 *
 *****    Copyright (c) CMU    1993      *****
 * Computer Science, Speech Group
 * Chengxiang Lu and Alex Hauptmann
 *
 * $Id: g722.h,v 1.26 2009/04/12 09:12:10 steveu Exp $
 */


/*! \file */

#if !defined(_SPANDSP_G722_H_)
#define _SPANDSP_G722_H_

/*! \page g722_page G.722 encoding and decoding
\section g722_page_sec_1 What does it do?
The G.722 module is a bit exact implementation of the ITU G.722 specification for all three
specified bit rates - 64000bps, 56000bps and 48000bps. It passes the ITU tests.

To allow fast and flexible interworking with narrow band telephony, the encoder and decoder
support an option for the linear audio to be an 8k samples/second stream. In this mode the
codec is considerably faster, and still fully compatible with wideband terminals using G.722.

\section g722_page_sec_2 How does it work?
???.
*/

enum
{
    G722_SAMPLE_RATE_8000 = 0x0001,
    G722_PACKED = 0x0002
};

/*!
    G.722 encode state
 */
typedef struct g722_encode_state_s g722_encode_state_t;

/*!
    G.722 decode state
 */
typedef struct g722_decode_state_s g722_decode_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise an G.722 encode context.
    \param s The G.722 encode context.
    \param rate The required bit rate for the G.722 data.
           The valid rates are 64000, 56000 and 48000.
    \param options
    \return A pointer to the G.722 encode context, or NULL for error. */
SPAN_DECLARE(g722_encode_state_t *) g722_encode_init(g722_encode_state_t *s, int rate, int options);

/*! Release a G.722 encode context.
    \param s The G.722 encode context.
    \return 0 for OK. */
SPAN_DECLARE(int) g722_encode_release(g722_encode_state_t *s);

/*! Free a G.722 encode context.
    \param s The G.722 encode context.
    \return 0 for OK. */
SPAN_DECLARE(int) g722_encode_free(g722_encode_state_t *s);

/*! Encode a buffer of linear PCM data to G.722
    \param s The G.722 context.
    \param g722_data The G.722 data produced.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of bytes of G.722 data produced. */
SPAN_DECLARE(int) g722_encode(g722_encode_state_t *s, uint8_t g722_data[], const int16_t amp[], int len);

/*! Initialise an G.722 decode context.
    \param s The G.722 decode context.
    \param rate The bit rate of the G.722 data.
           The valid rates are 64000, 56000 and 48000.
    \param options
    \return A pointer to the G.722 decode context, or NULL for error. */
SPAN_DECLARE(g722_decode_state_t *) g722_decode_init(g722_decode_state_t *s, int rate, int options);

/*! Release a G.722 decode context.
    \param s The G.722 decode context.
    \return 0 for OK. */
SPAN_DECLARE(int) g722_decode_release(g722_decode_state_t *s);

/*! Free a G.722 decode context.
    \param s The G.722 decode context.
    \return 0 for OK. */
SPAN_DECLARE(int) g722_decode_free(g722_decode_state_t *s);

/*! Decode a buffer of G.722 data to linear PCM.
    \param s The G.722 context.
    \param amp The audio sample buffer.
    \param g722_data
    \param len
    \return The number of samples returned. */
SPAN_DECLARE(int) g722_decode(g722_decode_state_t *s, int16_t amp[], const uint8_t g722_data[], int len);

#if defined(__cplusplus)
}
#endif

#endif
