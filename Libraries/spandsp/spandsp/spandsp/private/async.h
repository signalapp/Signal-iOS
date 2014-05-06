/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/async.h - Asynchronous serial bit stream encoding and decoding
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2003 Steve Underwood
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
 * $Id: async.h,v 1.1 2008/11/30 10:17:31 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_ASYNC_H_)
#define _SPANDSP_PRIVATE_ASYNC_H_

/*!
    Asynchronous data transmit descriptor. This defines the state of a single
    working instance of a byte to asynchronous serial converter, for use
    in FSK modems.
*/
struct async_tx_state_s
{
    /*! \brief The number of data bits per character. */
    int data_bits;
    /*! \brief The type of parity. */
    int parity;
    /*! \brief The number of stop bits per character. */
    int stop_bits;
    /*! \brief A pointer to the callback routine used to get characters to be transmitted. */
    get_byte_func_t get_byte;
    /*! \brief An opaque pointer passed when calling get_byte. */
    void *user_data;

    /*! \brief A current, partially transmitted, character. */
    int byte_in_progress;
    /*! \brief The current bit position within a partially transmitted character. */
    int bitpos;
    /*! \brief Parity bit. */
    int parity_bit;
};

/*!
    Asynchronous data receive descriptor. This defines the state of a single
    working instance of an asynchronous serial to byte converter, for use
    in FSK modems.
*/
struct async_rx_state_s
{
    /*! \brief The number of data bits per character. */
    int data_bits;
    /*! \brief The type of parity. */
    int parity;
    /*! \brief The number of stop bits per character. */
    int stop_bits;
    /*! \brief TRUE if V.14 rate adaption processing should be performed. */
    int use_v14;
    /*! \brief A pointer to the callback routine used to handle received characters. */
    put_byte_func_t put_byte;
    /*! \brief An opaque pointer passed when calling put_byte. */
    void *user_data;

    /*! \brief A current, partially complete, character. */
    int byte_in_progress;
    /*! \brief The current bit position within a partially complete character. */
    int bitpos;
    /*! \brief Parity bit. */
    int parity_bit;

    /*! A count of the number of parity errors seen. */
    int parity_errors;
    /*! A count of the number of character framing errors seen. */
    int framing_errors;
};

#endif
/*- End of file ------------------------------------------------------------*/
