/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/bitstream.h - Bitstream composition and decomposition routines.
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
 * $Id: bitstream.h,v 1.1.4.1 2009/12/28 12:20:47 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_BITSTREAM_H_)
#define _SPANDSP_PRIVATE_BITSTREAM_H_

/*! Bitstream handler state */
struct bitstream_state_s
{
    /*! The bit stream. */
    uint32_t bitstream;
    /*! The residual bits in bitstream. */
    int residue;
    /*! TRUE if the stream is LSB first, else MSB first */
    int lsb_first;
};


#endif
/*- End of file ------------------------------------------------------------*/
