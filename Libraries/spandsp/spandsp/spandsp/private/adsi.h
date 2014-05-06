/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/adsi.h - Analogue display services interface and other call ID related handling.
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
 * $Id: adsi.h,v 1.4 2009/04/12 04:20:01 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_ADSI_H_)
#define _SPANDSP_PRIVATE_ADSI_H_

/*!
    ADSI transmitter descriptor. This contains all the state information for an ADSI
    (caller ID, CLASS, CLIP, ACLIP) transmit channel.
 */
struct adsi_tx_state_s
{
    /*! */
    int standard;

    /*! */
    tone_gen_descriptor_t alert_tone_desc;
    /*! */
    tone_gen_state_t alert_tone_gen;
    /*! */
    fsk_tx_state_t fsktx;
    /*! */
    dtmf_tx_state_t dtmftx;
    /*! */
    async_tx_state_t asynctx;

    /*! */
    int tx_signal_on;

    /*! */
    int byte_no;
    /*! */
    int bit_pos;
    /*! */
    int bit_no;
    /*! */
    uint8_t msg[256];
    /*! */
    int msg_len;
    /*! */
    int preamble_len;
    /*! */
    int preamble_ones_len;
    /*! */
    int postamble_ones_len;
    /*! */
    int stop_bits;
    /*! */
    int baudot_shift;
    
    /*! */
    logging_state_t logging;
};

/*!
    ADSI receiver descriptor. This contains all the state information for an ADSI
    (caller ID, CLASS, CLIP, ACLIP, JCLIP) receive channel.
 */
struct adsi_rx_state_s
{
    /*! */
    int standard;
    /*! */
    put_msg_func_t put_msg;
    /*! */
    void *user_data;

    /*! */
    fsk_rx_state_t fskrx;
    /*! */
    dtmf_rx_state_t dtmfrx;

    /*! */
    int consecutive_ones;
    /*! */
    int bit_pos;
    /*! */
    int in_progress;
    /*! */
    uint8_t msg[256];
    /*! */
    int msg_len;
    /*! */
    int baudot_shift;
    
    /*! A count of the framing errors. */
    int framing_errors;

    /*! */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
