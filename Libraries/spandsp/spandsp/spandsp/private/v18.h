/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v18.h - V.18 text telephony for the deaf.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004-2009 Steve Underwood
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
 * $Id: v18.h,v 1.5 2009/11/04 15:52:06 steveu Exp $
 */
 
#if !defined(_SPANDSP_PRIVATE_V18_H_)
#define _SPANDSP_PRIVATE_V18_H_

struct v18_state_s
{
    /*! \brief TRUE if we are the calling modem */
    int calling_party;
    int mode;
    put_msg_func_t put_msg;
    void *user_data;

    union
    {
        queue_state_t queue;
        uint8_t buf[QUEUE_STATE_T_SIZE(128)];
    } queue;
    tone_gen_descriptor_t alert_tone_desc;
    tone_gen_state_t alert_tone_gen;
    fsk_tx_state_t fsktx;
    dtmf_tx_state_t dtmftx;
    async_tx_state_t asynctx;
    int baudot_tx_shift;
    int tx_signal_on;
    int byte_no;

    fsk_rx_state_t fskrx;
    dtmf_rx_state_t dtmfrx;
    int baudot_rx_shift;
    int consecutive_ones;
    uint8_t rx_msg[256 + 1];
    int rx_msg_len;
    int bit_pos;
    int in_progress;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
