/*
 * SpanDSP - a series of DSP components for telephony
 *
 * ima_adpcm.c - Conversion routines between linear 16 bit PCM data and
 *		         IMA/DVI/Intel ADPCM format.
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
 * Based on a bit from here, a bit from there, eye of toad,
 * ear of bat, etc - plus, of course, my own 2 cents.
 *
 * $Id: ima_adpcm.h,v 1.25 2009/04/11 18:11:19 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_IMA_ADPCM_H_)
#define _SPANDSP_IMA_ADPCM_H_

/*! \page ima_adpcm_page IMA/DVI/Intel ADPCM encoding and decoding
\section ima_adpcm_page_sec_1 What does it do?
IMA ADPCM offers a good balance of simplicity and quality at a rate of
32kbps.

\section ima_adpcm_page_sec_2 How does it work?

\section ima_adpcm_page_sec_3 How do I use it?
*/

enum
{
    /*! IMA4 is the original IMA ADPCM variant */
    IMA_ADPCM_IMA4 = 0,
    /*! DVI4 is the IMA ADPCM variant defined in RFC3551 */
    IMA_ADPCM_DVI4 = 1,
    /*! VDVI is the variable bit rate IMA ADPCM variant defined in RFC3551 */
    IMA_ADPCM_VDVI = 2
};

/*!
    IMA (DVI/Intel) ADPCM conversion state descriptor. This defines the state of
    a single working instance of the IMA ADPCM converter. This is used for
    either linear to ADPCM or ADPCM to linear conversion.
*/
typedef struct ima_adpcm_state_s ima_adpcm_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise an IMA ADPCM encode or decode context.
    \param s The IMA ADPCM context.
    \param variant IMA_ADPCM_IMA4, IMA_ADPCM_DVI4, or IMA_ADPCM_VDVI.
    \param chunk_size The size of a chunk, in samples. A chunk size of
           zero sample samples means treat each encode or decode operation
           as a chunk.
    \return A pointer to the IMA ADPCM context, or NULL for error. */
SPAN_DECLARE(ima_adpcm_state_t *) ima_adpcm_init(ima_adpcm_state_t *s,
                                                 int variant,
                                                 int chunk_size);

/*! Release an IMA ADPCM encode or decode context.
    \param s The IMA ADPCM context.
    \return 0 for OK. */
SPAN_DECLARE(int) ima_adpcm_release(ima_adpcm_state_t *s);

/*! Free an IMA ADPCM encode or decode context.
    \param s The IMA ADPCM context.
    \return 0 for OK. */
SPAN_DECLARE(int) ima_adpcm_free(ima_adpcm_state_t *s);

/*! Encode a buffer of linear PCM data to IMA ADPCM.
    \param s The IMA ADPCM context.
    \param ima_data The IMA ADPCM data produced.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of bytes of IMA ADPCM data produced. */
SPAN_DECLARE(int) ima_adpcm_encode(ima_adpcm_state_t *s,
                                   uint8_t ima_data[],
                                   const int16_t amp[],
                                   int len);

/*! Decode a buffer of IMA ADPCM data to linear PCM.
    \param s The IMA ADPCM context.
    \param amp The audio sample buffer.
    \param ima_data The IMA ADPCM data
    \param ima_bytes The number of bytes of IMA ADPCM data
    \return The number of samples returned. */
SPAN_DECLARE(int) ima_adpcm_decode(ima_adpcm_state_t *s,
                                   int16_t amp[],
                                   const uint8_t ima_data[],
                                   int ima_bytes);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
