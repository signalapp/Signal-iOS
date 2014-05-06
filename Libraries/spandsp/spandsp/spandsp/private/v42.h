/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v42.h
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
 * $Id: v42.h,v 1.2 2009/11/04 15:52:06 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_V42_H_)
#define _SPANDSP_PRIVATE_V42_H_

/*!
    LAP-M descriptor. This defines the working state for a single instance of LAP-M.
*/
struct lapm_state_s
{
    int handle;
    hdlc_rx_state_t hdlc_rx;
    hdlc_tx_state_t hdlc_tx;
    
    v42_frame_handler_t iframe_receive;
    void *iframe_receive_user_data;

    v42_status_func_t status_callback;
    void *status_callback_user_data;

    int state;
    int tx_waiting;
    int debug;
    /*! TRUE if originator. FALSE if answerer */
    int we_are_originator;
    /*! Remote network type (unknown, answerer. originator) */
    int peer_is_originator;
    /*! Next N(S) for transmission */
    int next_tx_frame;
    /*! The last of our frames which the peer acknowledged */
    int last_frame_peer_acknowledged;
    /*! Next N(R) for reception */
    int next_expected_frame;
    /*! The last of the peer's frames which we acknowledged */
    int last_frame_we_acknowledged;
    /*! TRUE if we sent an I or S frame with the F-bit set */
    int solicit_f_bit;
    /*! Retransmission count */
    int retransmissions;
    /*! TRUE if peer is busy */
    int busy;

    /*! Acknowledgement timer */
    int t401_timer;
    /*! Reply delay timer - optional */
    int t402_timer;
    /*! Inactivity timer - optional */
    int t403_timer;
    /*! Maximum number of octets in an information field */
    int n401;
    /*! Window size */
    int window_size_k;
	
    lapm_frame_queue_t *txqueue;
    lapm_frame_queue_t *tx_next;
    lapm_frame_queue_t *tx_last;
    queue_state_t *tx_queue;
    
    span_sched_state_t sched;
    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

/*!
    V.42 descriptor. This defines the working state for a single instance of V.42.
*/
struct v42_state_s
{
    /*! TRUE if we are the calling party, otherwise FALSE */
    int calling_party;
    /*! TRUE if we should detect whether the far end is V.42 capable. FALSE if we go
        directly to protocol establishment */
    int detect;

    /*! Stage in negotiating V.42 support */
    int rx_negotiation_step;
    int rxbits;
    int rxstream;
    int rxoks;
    int odp_seen;
    int txbits;
    int txstream;
    int txadps;
    /*! The LAP.M context */
    lapm_state_t lapm;

    /*! V.42 support detection timer */
    int t400_timer;
    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
