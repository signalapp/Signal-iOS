/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/t4_rx.h - definitions for T.4 FAX receive processing
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
 * $Id: t4_rx.h,v 1.6.2.8 2009/12/21 17:18:40 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_T4_RX_H_)
#define _SPANDSP_PRIVATE_T4_RX_H_

/*!
    TIFF specific state information to go with T.4 compression or decompression handling.
*/
typedef struct
{
    /*! \brief The current file name. */
    const char *file;
    /*! \brief The libtiff context for the current TIFF file */
    TIFF *tiff_file;

    /*! \brief The number of pages in the current image file. */
    int pages_in_file;

    /*! \brief The compression type for output to the TIFF file. */
    int32_t output_compression;
    /*! \brief The TIFF photometric setting for the current page. */
    uint16_t photo_metric;
    /*! \brief The TIFF fill order setting for the current page. */
    uint16_t fill_order;
    /*! \brief The TIFF G3 FAX options. */
    int32_t output_t4_options;

    /* "Background" information about the FAX, which can be stored in the image file. */
    /*! \brief The vendor of the machine which produced the file. */ 
    const char *vendor;
    /*! \brief The model of machine which produced the file. */ 
    const char *model;
    /*! \brief The local ident string. */ 
    const char *local_ident;
    /*! \brief The remote end's ident string. */ 
    const char *far_ident;
    /*! \brief The FAX sub-address. */ 
    const char *sub_address;
    /*! \brief The FAX DCS information, as an ASCII string. */ 
    const char *dcs;

    /*! \brief The first page to transfer. -1 to start at the beginning of the file. */
    int start_page;
    /*! \brief The last page to transfer. -1 to continue to the end of the file. */
    int stop_page;
} t4_tiff_state_t;

typedef struct t4_t6_decode_state_s t4_t6_decode_state_t;

/*!
    T.4 1D, T4 2D and T6 decompressor state.
*/
struct t4_t6_decode_state_s
{
    /*! \brief Callback function to write a row of pixels to the image destination. */
    t4_row_write_handler_t row_write_handler;
    /*! \brief Opaque pointer passed to row_write_handler. */
    void *row_write_user_data;

    /*! \brief Incoming bit buffer for decompression. */
    uint32_t rx_bitstream;
    /*! \brief The number of bits currently in rx_bitstream. */
    int rx_bits;
    /*! \brief The number of bits to be skipped before trying to match the next code word. */
    int rx_skip_bits;

    /*! \brief This variable is used to count the consecutive EOLS we have seen. If it
               reaches six, this is the end of the image. It is initially set to -1 for
               1D and 2D decoding, as an indicator that we must wait for the first EOL,
               before decoding any image data. */
    int consecutive_eols;

    /*! \brief The reference or starting changing element on the coding line. At the
               start of the coding line, a0 is set on an imaginary white changing element
               situated just before the first element on the line. During the coding of
               the coding line, the position of a0 is defined by the previous coding mode.
               (See T.4/4.2.1.3.2.). */
    int a0;
    /*! \brief The first changing element on the reference line to the right of a0 and of
               opposite colour to a0. */
    int b1;
    /*! \brief The length of the in-progress run of black or white. */
    int run_length;
    /*! \brief 2D horizontal mode control. */
    int black_white;
    /*! \brief TRUE if the current run is black */
    int its_black;

    /*! \brief The current step into the current row run-lengths buffer. */
    int a_cursor;
    /*! \brief The current step into the reference row run-lengths buffer. */
    int b_cursor;

    /*! \brief A pointer into the image buffer indicating where the last row begins */
    int last_row_starts_at;

    /*! \brief The current number of consecutive bad rows. */
    int curr_bad_row_run;
    /*! \brief The longest run of consecutive bad rows seen in the current page. */
    int longest_bad_row_run;
    /*! \brief The total number of bad rows in the current page. */
    int bad_rows;
};

#endif
/*- End of file ------------------------------------------------------------*/
