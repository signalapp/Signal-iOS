/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/fax_modems.h - definitions for the analogue modem set for fax processing
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2008 Steve Underwood
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
 * $Id: fax_modems.h,v 1.4 2009/09/04 14:38:47 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_FAX_MODEMS_H_)
#define _SPANDSP_PRIVATE_FAX_MODEMS_H_

/*!
    The set of modems needed for FAX, plus the auxilliary stuff, like tone generation.
*/
struct fax_modems_state_s
{
    /*! TRUE is talker echo protection should be sent for the image modems */
    int use_tep;

    /*! If TRUE, transmit silence when there is nothing else to transmit. If FALSE return only
        the actual generated audio. Note that this only affects untimed silences. Timed silences
        (e.g. the 75ms silence between V.21 and a high speed modem) will alway be transmitted as
        silent audio. */
    int transmit_on_idle;

    /*! \brief An HDLC context used when transmitting HDLC messages. */
    hdlc_tx_state_t hdlc_tx;
    /*! \brief An HDLC context used when receiving HDLC messages. */
    hdlc_rx_state_t hdlc_rx;
    /*! \brief A V.21 FSK modem context used when transmitting HDLC over V.21
               messages. */
    fsk_tx_state_t v21_tx;
    /*! \brief A V.21 FSK modem context used when receiving HDLC over V.21
               messages. */
    fsk_rx_state_t v21_rx;
    /*! \brief A V.17 modem context used when sending FAXes at 7200bps, 9600bps
               12000bps or 14400bps */
    v17_tx_state_t v17_tx;
    /*! \brief A V.29 modem context used when receiving FAXes at 7200bps, 9600bps
               12000bps or 14400bps */
    v17_rx_state_t v17_rx;
    /*! \brief A V.29 modem context used when sending FAXes at 7200bps or
               9600bps */
    v29_tx_state_t v29_tx;
    /*! \brief A V.29 modem context used when receiving FAXes at 7200bps or
               9600bps */
    v29_rx_state_t v29_rx;
    /*! \brief A V.27ter modem context used when sending FAXes at 2400bps or
               4800bps */
    v27ter_tx_state_t v27ter_tx;
    /*! \brief A V.27ter modem context used when receiving FAXes at 2400bps or
               4800bps */
    v27ter_rx_state_t v27ter_rx;
    /*! \brief Used to insert timed silences. */
    silence_gen_state_t silence_gen;
    /*! \brief CED or CNG generator */
    modem_connect_tones_tx_state_t connect_tx;
    /*! \brief CED or CNG detector */
    modem_connect_tones_rx_state_t connect_rx;
    /*! \brief */
    dc_restore_state_t dc_restore;

    /*! \brief The currently select receiver type */
    int current_rx_type;
    /*! \brief The currently select transmitter type */
    int current_tx_type;

    /*! \brief TRUE if a carrier is present. Otherwise FALSE. */
    int rx_signal_present;
    /*! \brief TRUE if a modem has trained correctly. */
    int rx_trained;
    /*! \brief TRUE if an HDLC frame has been received correctly. */
    int rx_frame_received;

    /*! The current receive signal handler */
    span_rx_handler_t *rx_handler;
    /*! The current receive missing signal fill-in handler */
    span_rx_fillin_handler_t *rx_fillin_handler;
    void *rx_user_data;

    /*! The current transmit signal handler */
    span_tx_handler_t *tx_handler;
    void *tx_user_data;

    /*! The next transmit signal handler, for two stage transmit operations.
        E.g. a short silence followed by a modem signal. */
    span_tx_handler_t *next_tx_handler;
    void *next_tx_user_data;

    /*! The current bit rate of the transmitter. */
    int tx_bit_rate;
    /*! The current bit rate of the receiver. */
    int rx_bit_rate;

    /*! If TRUE, transmission is in progress */
    int transmit;
    /*! \brief Audio logging file handle for received audio. */
    int audio_rx_log;
    /*! \brief Audio logging file handle for transmitted audio. */
    int audio_tx_log;
    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
