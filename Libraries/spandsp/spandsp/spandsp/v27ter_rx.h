/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v27ter_rx.h - ITU V.27ter modem receive part
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
 * $Id: v27ter_rx.h,v 1.61 2009/07/09 13:52:09 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_V27TER_RX_H_)
#define _SPANDSP_V27TER_RX_H_

/*! \page v27ter_rx_page The V.27ter receiver

\section v27ter_rx_page_sec_1 What does it do?
The V.27ter receiver implements the receive side of a V.27ter modem. This can operate
at data rates of 4800 and 2400 bits/s. The audio input is a stream of 16 bit samples,
at 8000 samples/second. The transmit and receive side of V.27ter modems operate
independantly. V.27ter is mostly used for FAX transmission, where it provides the
standard 4800 bits/s rate (the 2400 bits/s mode is not used for FAX). 

\section v27ter_rx_page_sec_2 How does it work?
V.27ter defines two modes of operation. One uses 8-PSK at 1600 baud, giving 4800bps.
The other uses 4-PSK at 1200 baud, giving 2400bps. A training sequence is specified
at the start of transmission, which makes the design of a V.27ter receiver relatively
straightforward.
*/

/*!
    V.27ter modem receive side descriptor. This defines the working state for a
    single instance of a V.27ter modem receiver.
*/
typedef struct v27ter_rx_state_s v27ter_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a V.27ter modem receive context.
    \brief Initialise a V.27ter modem receive context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 2400 and 4800.
    \param put_bit The callback routine used to put the received data.
    \param user_data An opaque pointer passed to the put_bit routine.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(v27ter_rx_state_t *) v27ter_rx_init(v27ter_rx_state_t *s, int bit_rate, put_bit_func_t put_bit, void *user_data);

/*! Reinitialise an existing V.27ter modem receive context.
    \brief Reinitialise an existing V.27ter modem receive context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 2400 and 4800.
    \param old_train TRUE if a previous trained values are to be reused.
    \return 0 for OK, -1 for bad parameter */
SPAN_DECLARE(int) v27ter_rx_restart(v27ter_rx_state_t *s, int bit_rate, int old_train);

/*! Release a V.27ter modem receive context.
    \brief Release a V.27ter modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v27ter_rx_release(v27ter_rx_state_t *s);

/*! Free a V.27ter modem receive context.
    \brief Free a V.27ter modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v27ter_rx_free(v27ter_rx_state_t *s);

/*! Get the logging context associated with a V.27ter modem receive context.
    \brief Get the logging context associated with a V.27ter modem receive context.
    \param s The modem context.
    \return A pointer to the logging context */
SPAN_DECLARE(logging_state_t *) v27ter_rx_get_logging_state(v27ter_rx_state_t *s);

/*! Change the put_bit function associated with a V.27ter modem receive context.
    \brief Change the put_bit function associated with a V.27ter modem receive context.
    \param s The modem context.
    \param put_bit The callback routine used to handle received bits.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v27ter_rx_set_put_bit(v27ter_rx_state_t *s, put_bit_func_t put_bit, void *user_data);

/*! Change the modem status report function associated with a V.27ter modem receive context.
    \brief Change the modem status report function associated with a V.27ter modem receive context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v27ter_rx_set_modem_status_handler(v27ter_rx_state_t *s, modem_rx_status_func_t handler, void *user_data);

/*! Process a block of received V.27ter modem audio samples.
    \brief Process a block of received V.27ter modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE_NONSTD(int) v27ter_rx(v27ter_rx_state_t *s, const int16_t amp[], int len);

/*! Fake processing of a missing block of received V.27ter modem audio samples.
    (e.g due to packet loss).
    \brief Fake processing of a missing block of received V.27ter modem audio samples.
    \param s The modem context.
    \param len The number of samples to fake.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE(int) v27ter_rx_fillin(v27ter_rx_state_t *s, int len);

/*! Get a snapshot of the current equalizer coefficients.
    \brief Get a snapshot of the current equalizer coefficients.
    \param coeffs The vector of complex coefficients.
    \return The number of coefficients in the vector. */
SPAN_DECLARE(int) v27ter_rx_equalizer_state(v27ter_rx_state_t *s, complexf_t **coeffs);

/*! Get the current received carrier frequency.
    \param s The modem context.
    \return The frequency, in Hertz. */
SPAN_DECLARE(float) v27ter_rx_carrier_frequency(v27ter_rx_state_t *s);

/*! Get the current symbol timing correction since startup.
    \param s The modem context.
    \return The correction. */
SPAN_DECLARE(float) v27ter_rx_symbol_timing_correction(v27ter_rx_state_t *s);

/*! Get a current received signal power.
    \param s The modem context.
    \return The signal power, in dBm0. */
SPAN_DECLARE(float) v27ter_rx_signal_power(v27ter_rx_state_t *s);

/*! Set the power level at which the carrier detection will cut in
    \param s The modem context.
    \param cutoff The signal cutoff power, in dBm0. */
SPAN_DECLARE(void) v27ter_rx_signal_cutoff(v27ter_rx_state_t *s, float cutoff);

/*! Set a handler routine to process QAM status reports
    \param s The modem context.
    \param handler The handler routine.
    \param user_data An opaque pointer passed to the handler routine. */
SPAN_DECLARE(void) v27ter_rx_set_qam_report_handler(v27ter_rx_state_t *s, qam_report_handler_t handler, void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
