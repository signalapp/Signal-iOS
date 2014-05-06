/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v42bis.h
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
 * $Id: v42bis.h,v 1.27 2009/04/11 18:11:19 steveu Exp $
 */

/*! \page v42bis_page V.42bis modem data compression
\section v42bis_page_sec_1 What does it do?
The v.42bis specification defines a data compression scheme, to work in
conjunction with the error correction scheme defined in V.42.

\section v42bis_page_sec_2 How does it work?
*/

#if !defined(_SPANDSP_V42BIS_H_)
#define _SPANDSP_V42BIS_H_

#define V42BIS_MAX_BITS         12
#define V42BIS_MAX_CODEWORDS    4096    /* 2^V42BIS_MAX_BITS */
#define V42BIS_TABLE_SIZE       5021    /* This should be a prime >(2^V42BIS_MAX_BITS) */
#define V42BIS_MAX_STRING_SIZE  250

enum
{
    V42BIS_P0_NEITHER_DIRECTION = 0,
    V42BIS_P0_INITIATOR_RESPONDER,
    V42BIS_P0_RESPONDER_INITIATOR,
    V42BIS_P0_BOTH_DIRECTIONS
};

enum
{
    V42BIS_COMPRESSION_MODE_DYNAMIC = 0,
    V42BIS_COMPRESSION_MODE_ALWAYS,
    V42BIS_COMPRESSION_MODE_NEVER
};

typedef void (*v42bis_frame_handler_t)(void *user_data, const uint8_t *pkt, int len);
typedef void (*v42bis_data_handler_t)(void *user_data, const uint8_t *buf, int len);

/*!
    V.42bis compression/decompression descriptor. This defines the working state for a
    single instance of V.42bis compress/decompression.
*/
typedef struct v42bis_state_s v42bis_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Compress a block of octets.
    \param s The V.42bis context.
    \param buf The data to be compressed.
    \param len The length of the data buffer.
    \return 0 */
SPAN_DECLARE(int) v42bis_compress(v42bis_state_t *s, const uint8_t *buf, int len);

/*! Flush out any data remaining in a compression buffer.
    \param s The V.42bis context.
    \return 0 */
SPAN_DECLARE(int) v42bis_compress_flush(v42bis_state_t *s);

/*! Decompress a block of octets.
    \param s The V.42bis context.
    \param buf The data to be decompressed.
    \param len The length of the data buffer.
    \return 0 */
SPAN_DECLARE(int) v42bis_decompress(v42bis_state_t *s, const uint8_t *buf, int len);
    
/*! Flush out any data remaining in the decompression buffer.
    \param s The V.42bis context.
    \return 0 */
SPAN_DECLARE(int) v42bis_decompress_flush(v42bis_state_t *s);

/*! Set the compression mode.
    \param s The V.42bis context.
    \param mode One of the V.42bis compression modes -
            V42BIS_COMPRESSION_MODE_DYNAMIC,
            V42BIS_COMPRESSION_MODE_ALWAYS,
            V42BIS_COMPRESSION_MODE_NEVER */
SPAN_DECLARE(void) v42bis_compression_control(v42bis_state_t *s, int mode);

/*! Initialise a V.42bis context.
    \param s The V.42bis context.
    \param negotiated_p0 The negotiated P0 parameter, from the V.42bis spec.
    \param negotiated_p1 The negotiated P1 parameter, from the V.42bis spec.
    \param negotiated_p2 The negotiated P2 parameter, from the V.42bis spec.
    \param frame_handler Frame callback handler.
    \param frame_user_data An opaque pointer passed to the frame callback handler.
    \param max_frame_len The maximum length that should be passed to the frame handler.
    \param data_handler data callback handler.
    \param data_user_data An opaque pointer passed to the data callback handler.
    \param max_data_len The maximum length that should be passed to the data handler.
    \return The V.42bis context. */
SPAN_DECLARE(v42bis_state_t *) v42bis_init(v42bis_state_t *s,
                                           int negotiated_p0,
                                           int negotiated_p1,
                                           int negotiated_p2,
                                           v42bis_frame_handler_t frame_handler,
                                           void *frame_user_data,
                                           int max_frame_len,
                                           v42bis_data_handler_t data_handler,
                                           void *data_user_data,
                                           int max_data_len);

/*! Release a V.42bis context.
    \param s The V.42bis context.
    \return 0 if OK */
SPAN_DECLARE(int) v42bis_release(v42bis_state_t *s);

/*! Free a V.42bis context.
    \param s The V.42bis context.
    \return 0 if OK */
SPAN_DECLARE(int) v42bis_free(v42bis_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
