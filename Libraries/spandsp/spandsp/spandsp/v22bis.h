/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v22bis.h - ITU V.22bis modem
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
 * $Id: v22bis.h,v 1.46 2009/11/04 15:52:06 steveu Exp $
 */

/*! \file */

/*! \page v22bis_page The V.22bis modem
\section v22bis_page_sec_1 What does it do?
The V.22bis modem is a duplex modem for general data use on the PSTN, at rates
of 1200 and 2400 bits/second. It is a compatible extension of the V.22 modem,
which is a 1200 bits/second only design. It is a band-split design, using carriers
of 1200Hz and 2400Hz. It is the fastest PSTN modem in general use which does not
use echo-cancellation.

\section v22bis__page_sec_2 How does it work?
V.22bis uses 4PSK modulation at 1200 bits/second or 16QAM modulation at 2400
bits/second. At 1200bps the symbols are so long that a fixed compromise equaliser
is sufficient to recover the 4PSK signal reliably. At 2400bps an adaptive
equaliser is necessary.

The V.22bis training sequence includes sections which allow the modems to determine
if the far modem can support (or is willing to support) 2400bps operation. The
modems will automatically use 2400bps if both ends are willing to use that speed,
or 1200bps if one or both ends to not acknowledge that 2400bps is OK.
*/

#if !defined(_SPANDSP_V22BIS_H_)
#define _SPANDSP_V22BIS_H_

enum
{
    V22BIS_GUARD_TONE_NONE,
    V22BIS_GUARD_TONE_550HZ,
    V22BIS_GUARD_TONE_1800HZ
};

/*!
    V.22bis modem descriptor. This defines the working state for a single instance
    of a V.22bis modem.
*/
typedef struct v22bis_state_s v22bis_state_t;

extern const complexf_t v22bis_constellation[16];

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Process a block of received V.22bis modem audio samples.
    \brief Process a block of received V.22bis modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE_NONSTD(int) v22bis_rx(v22bis_state_t *s, const int16_t amp[], int len);

/*! Fake processing of a missing block of received V.22bis modem audio samples.
    (e.g due to packet loss).
    \brief Fake processing of a missing block of received V.22bis modem audio samples.
    \param s The modem context.
    \param len The number of samples to fake.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) v22bis_rx_fillin(v22bis_state_t *s, int len);

/*! Get a snapshot of the current equalizer coefficients.
    \brief Get a snapshot of the current equalizer coefficients.
    \param coeffs The vector of complex coefficients.
    \return The number of coefficients in the vector. */
SPAN_DECLARE(int) v22bis_rx_equalizer_state(v22bis_state_t *s, complexf_t **coeffs);

/*! Get the current received carrier frequency.
    \param s The modem context.
    \return The frequency, in Hertz. */
SPAN_DECLARE(float) v22bis_rx_carrier_frequency(v22bis_state_t *s);

/*! Get the current symbol timing correction since startup.
    \param s The modem context.
    \return The correction. */
SPAN_DECLARE(float) v22bis_rx_symbol_timing_correction(v22bis_state_t *s);

/*! Get a current received signal power.
    \param s The modem context.
    \return The signal power, in dBm0. */
SPAN_DECLARE(float) v22bis_rx_signal_power(v22bis_state_t *s);

/*! Set the power level at which the carrier detection will cut in
    \param s The modem context.
    \param cutoff The signal cutoff power, in dBm0. */
SPAN_DECLARE(void) v22bis_rx_signal_cutoff(v22bis_state_t *s, float cutoff);

/*! Set a handler routine to process QAM status reports
    \param s The modem context.
    \param handler The handler routine.
    \param user_data An opaque pointer passed to the handler routine. */
SPAN_DECLARE(void) v22bis_rx_set_qam_report_handler(v22bis_state_t *s, qam_report_handler_t handler, void *user_data);

/*! Generate a block of V.22bis modem audio samples.
    \brief Generate a block of V.22bis modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples to be generated.
    \return The number of samples actually generated. */
SPAN_DECLARE_NONSTD(int) v22bis_tx(v22bis_state_t *s, int16_t amp[], int len);

/*! Adjust a V.22bis modem transmit context's power output.
    \brief Adjust a V.22bis modem transmit context's output power.
    \param s The modem context.
    \param power The power level, in dBm0 */
SPAN_DECLARE(void) v22bis_tx_power(v22bis_state_t *s, float power);

/*! Reinitialise an existing V.22bis modem context, so it may be reused.
    \brief Reinitialise an existing V.22bis modem context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 1200 and 2400.
    \return 0 for OK, -1 for bad parameter. */
SPAN_DECLARE(int) v22bis_restart(v22bis_state_t *s, int bit_rate);

/*! Request a retrain for a V.22bis modem context. A rate change may also be requested.
    \brief Request a retrain for a V.22bis modem context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 1200 and 2400.
    \return 0 for OK, -1 for request rejected. */
SPAN_DECLARE(int) v22bis_request_retrain(v22bis_state_t *s, int bit_rate);

/*! Request a loopback 2 for a V.22bis modem context.
    \brief Request a loopback 2 for a V.22bis modem context.
    \param s The modem context.
    \param enable TRUE to enable loopback, or FALSE to disable it.
    \return 0 for OK, -1 for request reject. */
SPAN_DECLARE(int) v22bis_remote_loopback(v22bis_state_t *s, int enable);

/*! Report the current operating bit rate of a V.22bis modem context.
    \brief Report the current operating bit rate of a V.22bis modem context
    \param s The modem context. */
SPAN_DECLARE(int) v22bis_current_bit_rate(v22bis_state_t *s);

/*! Initialise a V.22bis modem context. This must be called before the first
    use of the context, to initialise its contents.
    \brief Initialise a V.22bis modem context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 1200 and 2400.
    \param guard The guard tone option. 0 = none, 1 = 550Hz, 2 = 1800Hz.
    \param calling_party TRUE if this is the calling modem.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param put_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer, passed in calls to the get and put routines.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(v22bis_state_t *) v22bis_init(v22bis_state_t *s,
                                           int bit_rate,
                                           int guard,
                                           int calling_party,
                                           get_bit_func_t get_bit,
                                           void *get_bit_user_data,
                                           put_bit_func_t put_bit,
                                           void *put_bit_user_data);

/*! Release a V.22bis modem receive context.
    \brief Release a V.22bis modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v22bis_release(v22bis_state_t *s);

/*! Free a V.22bis modem receive context.
    \brief Free a V.22bis modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v22bis_free(v22bis_state_t *s);

/*! Get the logging context associated with a V.22bis modem context.
    \brief Get the logging context associated with a V.22bis modem context.
    \param s The modem context.
    \return A pointer to the logging context */
SPAN_DECLARE(logging_state_t *) v22bis_get_logging_state(v22bis_state_t *s);

/*! Change the get_bit function associated with a V.22bis modem context.
    \brief Change the get_bit function associated with a V.22bis modem context.
    \param s The modem context.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v22bis_set_get_bit(v22bis_state_t *s, get_bit_func_t get_bit, void *user_data);

/*! Change the get_bit function associated with a V.22bis modem context.
    \brief Change the put_bit function associated with a V.22bis modem context.
    \param s The modem context.
    \param put_bit The callback routine used to process the data received.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v22bis_set_put_bit(v22bis_state_t *s, put_bit_func_t put_bit, void *user_data);

/*! Change the modem status report function associated with a V.22bis modem receive context.
    \brief Change the modem status report function associated with a V.22bis modem receive context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v22bis_set_modem_status_handler(v22bis_state_t *s, modem_rx_status_func_t handler, void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
