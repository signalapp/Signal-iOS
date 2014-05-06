/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/ima_adpcm.c - Conversion routines between linear 16 bit PCM data
 *		                 and IMA/DVI/Intel ADPCM format.
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
 * $Id: ima_adpcm.h,v 1.1 2008/11/30 10:17:31 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_IMA_ADPCM_H_)
#define _SPANDSP_PRIVATE_IMA_ADPCM_H_

/*!
    IMA (DVI/Intel) ADPCM conversion state descriptor. This defines the state of
    a single working instance of the IMA ADPCM converter. This is used for
    either linear to ADPCM or ADPCM to linear conversion.
*/
struct ima_adpcm_state_s
{
    int variant;
    /*! \brief The size of a chunk, in samples. */
    int chunk_size;
    /*! \brief The last state of the ADPCM algorithm. */
    int last;
    /*! \brief Current index into the step size table. */
    int step_index;
    /*! \brief The current IMA code byte in progress. */
    uint16_t ima_byte;
    int bits;
};

#endif
/*- End of file ------------------------------------------------------------*/
