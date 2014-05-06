/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v8.h - V.8 modem negotiation processing.
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
 * $Id: v8.h,v 1.3.4.1 2009/12/28 12:20:47 steveu Exp $
 */
 
#if !defined(_SPANDSP_PRIVATE_V8_H_)
#define _SPANDSP_PRIVATE_V8_H_

struct v8_state_s
{
    /*! \brief TRUE if we are the calling modem */
    int calling_party;

    v8_result_handler_t *result_handler;
    void *result_handler_user_data;

    /*! \brief The current state of the V.8 protocol */
    int state;
    int fsk_tx_on;
    int modem_connect_tone_tx_on;
    int negotiation_timer;
    int ci_timer;
    int ci_count;
    fsk_tx_state_t v21tx;
    fsk_rx_state_t v21rx;
    queue_state_t *tx_queue;
    modem_connect_tones_tx_state_t ansam_tx;
    modem_connect_tones_rx_state_t ansam_rx;

    /*! \brief Modulation schemes available at this end. */
    unsigned int far_end_modulations;

    v8_parms_t parms;
    v8_parms_t result;

    /* V.8 data parsing */
    uint32_t bit_stream;
    int bit_cnt;
    /* Indicates the type of message coming up */
    int preamble_type;
    uint8_t rx_data[64];
    int rx_data_ptr;
    
    /*! \brief a reference copy of the last CM or JM message, used when
               testing for matches. */
    uint8_t cm_jm_data[64];
    int cm_jm_len;
    int got_cm_jm;
    int got_cj;
    int zero_byte_count;
    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
