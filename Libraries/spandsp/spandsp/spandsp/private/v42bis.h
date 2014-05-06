/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v42bis.h
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
 * $Id: v42bis.h,v 1.1 2008/11/15 14:43:08 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_V42BIS_H_)
#define _SPANDSP_PRIVATE_V42BIS_H_

/*!
    V.42bis dictionary node.
*/
typedef struct
{
    /*! \brief The prior code for each defined code. */
    uint16_t parent_code;
    /*! \brief The number of leaf nodes this node has */
    int16_t leaves;
    /*! \brief This leaf octet for each defined code. */
    uint8_t node_octet;
    /*! \brief Bit map of the children which exist */
    uint32_t children[8];
} v42bis_dict_node_t;

/*!
    V.42bis compression. This defines the working state for a single instance
    of V.42bis compression.
*/
typedef struct
{
    /*! \brief Compression mode. */
    int compression_mode;
    /*! \brief Callback function to handle received frames. */
    v42bis_frame_handler_t handler;
    /*! \brief An opaque pointer passed in calls to frame_handler. */
    void *user_data;
    /*! \brief The maximum frame length allowed */
    int max_len;

    uint32_t string_code;
    uint32_t latest_code;
    int string_length;
    uint32_t output_bit_buffer;
    int output_bit_count;
    int output_octet_count;
    uint8_t output_buf[1024];
    v42bis_dict_node_t dict[V42BIS_MAX_CODEWORDS];
    /*! \brief TRUE if we are in transparent (i.e. uncompressable) mode */
    int transparent;
    int change_transparency;
    /*! \brief IIR filter state, used in assessing compressibility. */
    int compressibility_filter;
    int compressibility_persistence;
    
    /*! \brief Next empty dictionary entry */
    uint32_t v42bis_parm_c1;
    /*! \brief Current codeword size */
    int v42bis_parm_c2;
    /*! \brief Threshold for codeword size change */
    uint32_t v42bis_parm_c3;

    /*! \brief Mark that this is the first octet/code to be processed */
    int first;
    uint8_t escape_code;
} v42bis_compress_state_t;

/*!
    V.42bis decompression. This defines the working state for a single instance
    of V.42bis decompression.
*/
typedef struct
{
    /*! \brief Callback function to handle decompressed data. */
    v42bis_data_handler_t handler;
    /*! \brief An opaque pointer passed in calls to data_handler. */
    void *user_data;
    /*! \brief The maximum decompressed data block length allowed */
    int max_len;

    uint32_t old_code;
    uint32_t last_old_code;
    uint32_t input_bit_buffer;
    int input_bit_count;
    int octet;
    int last_length;
    int output_octet_count;
    uint8_t output_buf[1024];
    v42bis_dict_node_t dict[V42BIS_MAX_CODEWORDS];
    /*! \brief TRUE if we are in transparent (i.e. uncompressable) mode */
    int transparent;

    int last_extra_octet;

    /*! \brief Next empty dictionary entry */
    uint32_t v42bis_parm_c1;
    /*! \brief Current codeword size */
    int v42bis_parm_c2;
    /*! \brief Threshold for codeword size change */
    uint32_t v42bis_parm_c3;
        
    /*! \brief Mark that this is the first octet/code to be processed */
    int first;
    uint8_t escape_code;
    int escaped;
} v42bis_decompress_state_t;

/*!
    V.42bis compression/decompression descriptor. This defines the working state for a
    single instance of V.42bis compress/decompression.
*/
struct v42bis_state_s
{
    /*! \brief V.42bis data compression directions. */
    int v42bis_parm_p0;

    /*! \brief Compression state. */
    v42bis_compress_state_t compress;
    /*! \brief Decompression state. */
    v42bis_decompress_state_t decompress;
    
    /*! \brief Maximum codeword size (bits) */
    int v42bis_parm_n1;
    /*! \brief Total number of codewords */
    uint32_t v42bis_parm_n2;
    /*! \brief Maximum string length */
    int v42bis_parm_n7;
};

#endif
/*- End of file ------------------------------------------------------------*/
