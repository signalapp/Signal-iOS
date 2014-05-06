/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/g722.h - The ITU G.722 codec.
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
 * $Id: g722.h,v 1.2 2009/04/12 09:12:11 steveu Exp $
 */


/*! \file */

#if !defined(_SPANDSP_PRIVATE_G722_H_)
#define _SPANDSP_PRIVATE_G722_H_

/*! The per band parameters for both encoding and decoding G.722 */
typedef struct
{
    int16_t nb;
    int16_t det;
    int16_t s;
    int16_t sz;
    int16_t r;
    int16_t p[2];
    int16_t a[2];
    int16_t b[6];
    int16_t d[7];
} g722_band_t;

/*!
    G.722 encode state
 */
struct g722_encode_state_s
{
    /*! TRUE if the operating in the special ITU test mode, with the band split filters
             disabled. */
    int itu_test_mode;
    /*! TRUE if the G.722 data is packed */
    int packed;
    /*! TRUE if encode from 8k samples/second */
    int eight_k;
    /*! 6 for 48000kbps, 7 for 56000kbps, or 8 for 64000kbps. */
    int bits_per_sample;

    /*! Signal history for the QMF */
    int16_t x[12];
    int16_t y[12];
    int ptr;

    g722_band_t band[2];

    uint32_t in_buffer;
    int in_bits;
    uint32_t out_buffer;
    int out_bits;
};

/*!
    G.722 decode state
 */
struct g722_decode_state_s
{
    /*! TRUE if the operating in the special ITU test mode, with the band split filters
             disabled. */
    int itu_test_mode;
    /*! TRUE if the G.722 data is packed */
    int packed;
    /*! TRUE if decode to 8k samples/second */
    int eight_k;
    /*! 6 for 48000kbps, 7 for 56000kbps, or 8 for 64000kbps. */
    int bits_per_sample;

    /*! Signal history for the QMF */
    int16_t x[12];
    int16_t y[12];
    int ptr;

    g722_band_t band[2];
    
    uint32_t in_buffer;
    int in_bits;
    uint32_t out_buffer;
    int out_bits;
};

#endif
/*- End of file ------------------------------------------------------------*/
