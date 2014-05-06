/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/at_interpreter.h - AT command interpreter to V.251, V.252, V.253, T.31 and the 3GPP specs.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004, 2005, 2006 Steve Underwood
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
 * $Id: at_interpreter.h,v 1.1 2008/11/30 05:43:37 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_AT_INTERPRETER_H_)
#define _SPANDSP_PRIVATE_AT_INTERPRETER_H_

typedef struct at_call_id_s at_call_id_t;

struct at_call_id_s
{
    char *id;
    char *value;
    at_call_id_t *next;
};

/*!
    AT descriptor. This defines the working state for a single instance of
    the AT interpreter.
*/
struct at_state_s
{
    at_profile_t p;
    /*! Value set by +GCI */
    int country_of_installation;
    /*! Value set by +FIT */
    int dte_inactivity_timeout;
    /*! Value set by +FIT */
    int dte_inactivity_action;
    /*! Value set by L */
    int speaker_volume;
    /*! Value set by M */
    int speaker_mode;
    /*! This is no real DTE rate. This variable is for compatibility this serially
        connected modems. */
    /*! Value set by +IPR/+FPR */
    int dte_rate;
    /*! Value set by +ICF */
    int dte_char_format;
    /*! Value set by +ICF */
    int dte_parity;
    /*! Value set by &C */
    int rlsd_behaviour;
    /*! Value set by &D */
    int dtr_behaviour;
    /*! Value set by +FCL */
    int carrier_loss_timeout;
    /*! Value set by X */
    int result_code_mode;
    /*! Value set by +IDSR */
    int dsr_option;
    /*! Value set by +ILSD */
    int long_space_disconnect_option;
    /*! Value set by +ICLOK */
    int sync_tx_clock_source;
    /*! Value set by +EWIND */
    int rx_window;
    /*! Value set by +EWIND */
    int tx_window;
    
    int v8bis_signal;
    int v8bis_1st_message;
    int v8bis_2nd_message;
    int v8bis_sig_en;
    int v8bis_msg_en;
    int v8bis_supp_delay;

    uint8_t rx_data[256];
    int rx_data_bytes;

    int display_call_info;
    int call_info_displayed;
    at_call_id_t *call_id;
    char *local_id;
    /*! The currently select FAX modem class. 0 = data modem mode. */
    int fclass_mode;
    int at_rx_mode;
    int rings_indicated;
    int do_hangup;
    int silent_dial;
    int command_dial;
    int ok_is_pending;
    int dte_is_waiting;
    /*! \brief TRUE if a carrier is presnt. Otherwise FALSE. */
    int rx_signal_present;
    /*! \brief TRUE if a modem has trained, Otherwise FALSE. */
    int rx_trained;
    int transmit;

    char line[256];
    int line_ptr;

    at_modem_control_handler_t *modem_control_handler;
    void *modem_control_user_data;
    at_tx_handler_t *at_tx_handler;
    void *at_tx_user_data;
    at_class1_handler_t *class1_handler;
    void *class1_user_data;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
