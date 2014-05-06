/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/t38_non_ecm_buffer.h - A rate adapting buffer for T.38 non-ECM image
 *                                and TCF data
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005, 2006, 2007, 2008 Steve Underwood
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
 * $Id: t38_non_ecm_buffer.h,v 1.2.4.1 2009/12/19 06:43:28 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_T38_NON_ECM_BUFFER_H_)
#define _SPANDSP_PRIVATE_T38_NON_ECM_BUFFER_H_

/*! \brief A flow controlled non-ECM image data buffer, for buffering T.38 to analogue
           modem data.
*/
struct t38_non_ecm_buffer_state_s
{
    /*! \brief Minimum number of bits per row, used when fill bits are being deleted on the
               link, and restored at the emitting gateway. */
    int min_bits_per_row;

    /*! \brief non-ECM modem transmit data buffer. */
    uint8_t data[T38_NON_ECM_TX_BUF_LEN];
    /*! \brief The current write point in the buffer. */
    int in_ptr;
    /*! \brief The current read point in the buffer. */
    int out_ptr;
    /*! \brief The location of the most recent EOL marker in the buffer. */
    int latest_eol_ptr;
    /*! \brief The number of bits to date in the current row, used when min_row_bits is
               to be applied. */
    int row_bits;

    /*! \brief The bit stream entering the buffer, used to detect EOLs */
    unsigned int bit_stream;
    /*! \brief The non-ECM flow control fill octet (0xFF before the first data, and 0x00
               once data has started). */
    uint8_t flow_control_fill_octet;
    /*! \brief A code for the phase of input buffering, from initial all ones to completion. */
    int input_phase;
    /*! \brief TRUE is the end of non-ECM data indication has been received. */
    int data_finished;
    /*! \brief The current octet being transmitted from the buffer. */
    unsigned int octet;
    /*! \brief The current bit number in the current non-ECM octet. */
    int bit_no;
    /*! \brief TRUE if in image data mode, as opposed to TCF mode. */
    int image_data_mode;

    /*! \brief The number of octets input to the buffer. */
    int in_octets;
    /*! \brief The number of rows input to the buffer. */
    int in_rows;
    /*! \brief The number of non-ECM fill octets generated for minimum row bits
               purposes. */
    int min_row_bits_fill_octets;
    /*! \brief The number of octets output from the buffer. */
    int out_octets;
    /*! \brief The number of rows output from the buffer. */
    int out_rows;
    /*! \brief The number of non-ECM fill octets generated for flow control
               purposes. */
    int flow_control_fill_octets;
};

#endif
/*- End of file ------------------------------------------------------------*/
