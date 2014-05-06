/*
 * SpanDSP - a series of DSP components for telephony
 *
 * g726.h - ITU G.726 codec.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2006 Steve Underwood
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
 * $Id: g726.h,v 1.26 2009/04/12 09:12:10 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_G726_H_)
#define _SPANDSP_G726_H_

/*! \page g726_page G.726 encoding and decoding
\section g726_page_sec_1 What does it do?

The G.726 module is a bit exact implementation of the full ITU G.726 specification.
It supports:
    - 16 kbps, 24kbps, 32kbps, and 40kbps operation.
    - Tandem adjustment, for interworking with A-law and u-law.
    - Annex A support, for use in environments not using A-law or u-law.

It passes the ITU tests.

\section g726_page_sec_2 How does it work?
???.
*/

enum
{
    G726_ENCODING_LINEAR = 0,   /* Interworking with 16 bit signed linear */
    G726_ENCODING_ULAW,         /* Interworking with u-law */
    G726_ENCODING_ALAW          /* Interworking with A-law */
};

enum
{
    G726_PACKING_NONE = 0,
    G726_PACKING_LEFT = 1,
    G726_PACKING_RIGHT = 2
};

/*!
    G.726 state
 */
typedef struct g726_state_s g726_state_t;

typedef int16_t (*g726_decoder_func_t)(g726_state_t *s, uint8_t code);

typedef uint8_t (*g726_encoder_func_t)(g726_state_t *s, int16_t amp);

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a G.726 encode or decode context.
    \param s The G.726 context.
    \param bit_rate The required bit rate for the ADPCM data.
           The valid rates are 16000, 24000, 32000 and 40000.
    \param ext_coding The coding used outside G.726.
    \param packing One of the G.726_PACKING_xxx options.
    \return A pointer to the G.726 context, or NULL for error. */
SPAN_DECLARE(g726_state_t *) g726_init(g726_state_t *s, int bit_rate, int ext_coding, int packing);

/*! Release a G.726 encode or decode context.
    \param s The G.726 context.
    \return 0 for OK. */
SPAN_DECLARE(int) g726_release(g726_state_t *s);

/*! Free a G.726 encode or decode context.
    \param s The G.726 context.
    \return 0 for OK. */
SPAN_DECLARE(int) g726_free(g726_state_t *s);

/*! Decode a buffer of G.726 ADPCM data to linear PCM, a-law or u-law.
    \param s The G.726 context.
    \param amp The audio sample buffer.
    \param g726_data
    \param g726_bytes
    \return The number of samples returned. */
SPAN_DECLARE(int) g726_decode(g726_state_t *s,
                              int16_t amp[],
                              const uint8_t g726_data[],
                              int g726_bytes);

/*! Encode a buffer of linear PCM data to G.726 ADPCM.
    \param s The G.726 context.
    \param g726_data The G.726 data produced.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of bytes of G.726 data produced. */
SPAN_DECLARE(int) g726_encode(g726_state_t *s,
                              uint8_t g726_data[],
                              const int16_t amp[],
                              int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
