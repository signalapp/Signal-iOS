/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/g726.h - ITU G.726 codec.
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
 * $Id: g726.h,v 1.4 2009/04/12 09:12:11 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_G726_H_)
#define _SPANDSP_PRIVATE_G726_H_

/*!
 * The following is the definition of the state structure
 * used by the G.726 encoder and decoder to preserve their internal
 * state between successive calls.  The meanings of the majority
 * of the state structure fields are explained in detail in the
 * ITU Recommendation G.726.  The field names are essentially indentical
 * to variable names in the bit level description of the coding algorithm
 * included in this recommendation.
 */
struct g726_state_s
{
    /*! The bit rate */
    int rate;
    /*! The external coding, for tandem operation */
    int ext_coding;
    /*! The number of bits per sample */
    int bits_per_sample;
    /*! One of the G.726_PACKING_xxx options */
    int packing;

    /*! Locked or steady state step size multiplier. */
    int32_t yl;
    /*! Unlocked or non-steady state step size multiplier. */
    int16_t yu;
    /*! int16_t term energy estimate. */
    int16_t dms;
    /*! Long term energy estimate. */
    int16_t dml;
    /*! Linear weighting coefficient of 'yl' and 'yu'. */
    int16_t ap;
    
    /*! Coefficients of pole portion of prediction filter. */
    int16_t a[2];
    /*! Coefficients of zero portion of prediction filter. */
    int16_t b[6];
    /*! Signs of previous two samples of a partially reconstructed signal. */
    int16_t pk[2];
    /*! Previous 6 samples of the quantized difference signal represented in
        an internal floating point format. */
    int16_t dq[6];
    /*! Previous 2 samples of the quantized difference signal represented in an
        internal floating point format. */
    int16_t sr[2];
    /*! Delayed tone detect */
    int td;
    
    /*! \brief The bit stream processing context. */
    bitstream_state_t bs;

    /*! \brief The current encoder function. */
    g726_encoder_func_t enc_func;
    /*! \brief The current decoder function. */
    g726_decoder_func_t dec_func;
};

#endif
/*- End of file ------------------------------------------------------------*/
