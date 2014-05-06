/*
 * SpanDSP - a series of DSP components for telephony
 *
 * gsm0610.h - GSM 06.10 full rate speech codec.
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
 * $Id: gsm0610.h,v 1.21 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_GSM0610_H_)
#define _SPANDSP_GSM0610_H_

/*! \page gsm0610_page GSM 06.10 encoding and decoding
\section gsm0610_page_sec_1 What does it do?

The GSM 06.10 module is an version of the widely used GSM FR codec software
available from http://kbs.cs.tu-berlin.de/~jutta/toast.html. This version
was produced since some versions of this codec are not bit exact, or not
very efficient on modern processors. This implementation can use MMX instructions
on Pentium class processors, or alternative methods on other processors. It
passes all the ETSI test vectors. That is, it is a tested bit exact implementation.

This implementation supports encoded data in one of three packing formats:
    - Unpacked, with the 76 parameters of a GSM 06.10 code frame each occupying a
      separate byte. (note that none of the parameters exceed 8 bits).
    - Packed the the 33 byte per frame, used for VoIP, where 4 bits per frame are wasted.
    - Packed in WAV49 format, where 2 frames are packed into 65 bytes.

\section gsm0610_page_sec_2 How does it work?
???.
*/

enum
{
    GSM0610_PACKING_NONE,
    GSM0610_PACKING_WAV49,
    GSM0610_PACKING_VOIP
};

/*!
    GSM 06.10 FR codec unpacked frame.
*/
typedef struct
{
    int16_t LARc[8];
    int16_t Nc[4];
    int16_t bc[4];
    int16_t Mc[4];
    int16_t xmaxc[4];
    int16_t xMc[4][13];
} gsm0610_frame_t;

/*!
    GSM 06.10 FR codec state descriptor. This defines the state of
    a single working instance of the GSM 06.10 FR encoder or decoder.
*/
typedef struct gsm0610_state_s gsm0610_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a GSM 06.10 encode or decode context.
    \param s The GSM 06.10 context
    \param packing One of the GSM0610_PACKING_xxx options.
    \return A pointer to the GSM 06.10 context, or NULL for error. */
SPAN_DECLARE(gsm0610_state_t *) gsm0610_init(gsm0610_state_t *s, int packing);

/*! Release a GSM 06.10 encode or decode context.
    \param s The GSM 06.10 context
    \return 0 for success, else -1. */
SPAN_DECLARE(int) gsm0610_release(gsm0610_state_t *s);

/*! Free a GSM 06.10 encode or decode context.
    \param s The GSM 06.10 context
    \return 0 for success, else -1. */
SPAN_DECLARE(int) gsm0610_free(gsm0610_state_t *s);

/*! Set the packing format for a GSM 06.10 encode or decode context.
    \param s The GSM 06.10 context
    \param packing One of the GSM0610_PACKING_xxx options.
    \return 0 for success, else -1. */
SPAN_DECLARE(int) gsm0610_set_packing(gsm0610_state_t *s, int packing);

/*! Encode a buffer of linear PCM data to GSM 06.10.
    \param s The GSM 06.10 context.
    \param code The GSM 06.10 data produced.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of bytes of GSM 06.10 data produced. */
SPAN_DECLARE(int) gsm0610_encode(gsm0610_state_t *s, uint8_t code[], const int16_t amp[], int len);

/*! Decode a buffer of GSM 06.10 data to linear PCM.
    \param s The GSM 06.10 context.
    \param amp The audio sample buffer.
    \param code The GSM 06.10 data.
    \param len The number of bytes of GSM 06.10 data to be decoded.
    \return The number of samples returned. */
SPAN_DECLARE(int) gsm0610_decode(gsm0610_state_t *s, int16_t amp[], const uint8_t code[], int len);

SPAN_DECLARE(int) gsm0610_pack_none(uint8_t c[], const gsm0610_frame_t *s);

/*! Pack a pair of GSM 06.10 frames in the format used for wave files (wave type 49).
    \param c The buffer for the packed data. This must be at least 65 bytes long.
    \param s A pointer to the frames to be packed.
    \return The number of bytes generated. */
SPAN_DECLARE(int) gsm0610_pack_wav49(uint8_t c[], const gsm0610_frame_t *s);

/*! Pack a GSM 06.10 frames in the format used for VoIP.
    \param c The buffer for the packed data. This must be at least 33 bytes long.
    \param s A pointer to the frame to be packed.
    \return The number of bytes generated. */
SPAN_DECLARE(int) gsm0610_pack_voip(uint8_t c[], const gsm0610_frame_t *s);

SPAN_DECLARE(int) gsm0610_unpack_none(gsm0610_frame_t *s, const uint8_t c[]);

/*! Unpack a pair of GSM 06.10 frames from the format used for wave files (wave type 49).
    \param s A pointer to a buffer into which the frames will be packed.
    \param c The buffer containing the data to be unpacked. This must be at least 65 bytes long.
    \return The number of bytes absorbed. */
SPAN_DECLARE(int) gsm0610_unpack_wav49(gsm0610_frame_t *s, const uint8_t c[]);

/*! Unpack a GSM 06.10 frame from the format used for VoIP.
    \param s A pointer to a buffer into which the frame will be packed.
    \param c The buffer containing the data to be unpacked. This must be at least 33 bytes long.
    \return The number of bytes absorbed. */
SPAN_DECLARE(int) gsm0610_unpack_voip(gsm0610_frame_t *s, const uint8_t c[]);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of include ---------------------------------------------------------*/
