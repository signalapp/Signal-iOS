/*
 * SpanDSP - a series of DSP components for telephony
 *
 * lpc10.h - LPC10 low bit rate speech codec.
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
 * $Id: lpc10.h,v 1.22 2009/04/11 18:11:19 steveu Exp $
 */

#if !defined(_SPANDSP_LPC10_H_)
#define _SPANDSP_LPC10_H_

/*! \page lpc10_page LPC10 encoding and decoding
\section lpc10_page_sec_1 What does it do?
The LPC10 module implements the US Department of Defense LPC10
codec. This codec produces compressed data at 2400bps. At such
a low rate high fidelity cannot be expected. However, the speech
clarity is quite good, and this codec is unencumbered by patent
or other restrictions.

\section lpc10_page_sec_2 How does it work?
???.
*/

#define LPC10_SAMPLES_PER_FRAME 180
#define LPC10_BITS_IN_COMPRESSED_FRAME 54

/*!
    LPC10 codec unpacked frame.
*/
typedef struct
{
    /*! Pitch */
    int32_t ipitch;
    /*! Energy */
    int32_t irms;
    /*! Reflection coefficients */
    int32_t irc[10];
} lpc10_frame_t;

/*!
    LPC10 codec encoder state descriptor. This defines the state of
    a single working instance of the LPC10 encoder.
*/
typedef struct lpc10_encode_state_s lpc10_encode_state_t;

/*!
    LPC10 codec decoder state descriptor. This defines the state of
    a single working instance of the LPC10 decoder.
*/
typedef struct lpc10_decode_state_s lpc10_decode_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise an LPC10e encode context.
    \param s The LPC10e context
    \param error_correction ???
    \return A pointer to the LPC10e context, or NULL for error. */
SPAN_DECLARE(lpc10_encode_state_t *) lpc10_encode_init(lpc10_encode_state_t *s, int error_correction);

SPAN_DECLARE(int) lpc10_encode_release(lpc10_encode_state_t *s);

SPAN_DECLARE(int) lpc10_encode_free(lpc10_encode_state_t *s);

/*! Encode a buffer of linear PCM data to LPC10e.
    \param s The LPC10e context.
    \param ima_data The LPC10e data produced.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer. This must be a multiple of 180, as
           this is the number of samples on a frame.
    \return The number of bytes of LPC10e data produced. */
SPAN_DECLARE(int) lpc10_encode(lpc10_encode_state_t *s, uint8_t code[], const int16_t amp[], int len);

/*! Initialise an LPC10e decode context.
    \param s The LPC10e context
    \param error_correction ???
    \return A pointer to the LPC10e context, or NULL for error. */
SPAN_DECLARE(lpc10_decode_state_t *) lpc10_decode_init(lpc10_decode_state_t *st, int error_correction);

SPAN_DECLARE(int) lpc10_decode_release(lpc10_decode_state_t *s);

SPAN_DECLARE(int) lpc10_decode_free(lpc10_decode_state_t *s);

/*! Decode a buffer of LPC10e data to linear PCM.
    \param s The LPC10e context.
    \param amp The audio sample buffer.
    \param code The LPC10e data.
    \param len The number of bytes of LPC10e data to be decoded. This must be a multiple of 7,
           as each frame is packed into 7 bytes.
    \return The number of samples returned. */
SPAN_DECLARE(int) lpc10_decode(lpc10_decode_state_t *s, int16_t amp[], const uint8_t code[], int len);


#if defined(__cplusplus)
}
#endif

#endif
/*- End of include ---------------------------------------------------------*/
