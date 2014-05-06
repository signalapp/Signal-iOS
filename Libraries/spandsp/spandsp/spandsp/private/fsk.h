/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/fsk.h - FSK modem transmit and receive parts
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
 * $Id: fsk.h,v 1.5 2009/04/01 13:22:40 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_FSK_H_)
#define _SPANDSP_PRIVATE_FSK_H_

/*!
    FSK modem transmit descriptor. This defines the state of a single working
    instance of an FSK modem transmitter.
*/
struct fsk_tx_state_s
{
    int baud_rate;
    /*! \brief The callback function used to get the next bit to be transmitted. */
    get_bit_func_t get_bit;
    /*! \brief A user specified opaque pointer passed to the get_bit function. */
    void *get_bit_user_data;

    /*! \brief The callback function used to report modem status changes. */
    modem_tx_status_func_t status_handler;
    /*! \brief A user specified opaque pointer passed to the status function. */
    void *status_user_data;

    int32_t phase_rates[2];
    int16_t scaling;
    int32_t current_phase_rate;
    uint32_t phase_acc;
    int baud_frac;
    int shutdown;
};

/*!
    FSK modem receive descriptor. This defines the state of a single working
    instance of an FSK modem receiver.
*/
struct fsk_rx_state_s
{
    int baud_rate;
    /*! \brief Synchronous/asynchronous framing control */
    int framing_mode;
    /*! \brief The callback function used to put each bit received. */
    put_bit_func_t put_bit;
    /*! \brief A user specified opaque pointer passed to the put_bit routine. */
    void *put_bit_user_data;

    /*! \brief The callback function used to report modem status changes. */
    modem_tx_status_func_t status_handler;
    /*! \brief A user specified opaque pointer passed to the status function. */
    void *status_user_data;

    int32_t carrier_on_power;
    int32_t carrier_off_power;
    power_meter_t power;
    /*! \brief The value of the last signal sample, using the a simple HPF for signal power estimation. */
    int16_t last_sample;
    /*! \brief >0 if a signal above the minimum is present. It may or may not be a V.29 signal. */
    int signal_present;

    int32_t phase_rate[2];
    uint32_t phase_acc[2];

    int correlation_span;

    complexi32_t window[2][FSK_MAX_WINDOW_LEN];
    complexi32_t dot[2];
    int buf_ptr;

    int frame_state;
    int frame_bits;
    int baud_phase;
    int last_bit;
    int scaling_shift;
};

#endif
/*- End of file ------------------------------------------------------------*/
