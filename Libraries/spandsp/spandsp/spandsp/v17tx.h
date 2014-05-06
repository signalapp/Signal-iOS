/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v17tx.h - ITU V.17 modem transmit part
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
 * $Id: v17tx.h,v 1.43.4.1 2009/12/24 16:52:30 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_V17TX_H_)
#define _SPANDSP_V17TX_H_

/*! \page v17tx_page The V.17 transmitter
\section v17tx_page_sec_1 What does it do?
The V.17 transmitter implements the transmit side of a V.17 modem. This can
operate at data rates of 14400, 12000, 9600 and 7200 bits/second. The audio
output is a stream of 16 bit samples, at 8000 samples/second. The transmit and
receive side of V.17 modems operate independantly. V.17 is mostly used for FAX
transmission, where it provides the standard 14400 bits/second rate. 

\section v17tx_page_sec_2 How does it work?
V.17 uses QAM modulation and trellis coding. The data to be transmitted is
scrambled, to whiten it. The least significant 2 bits of each symbol are then
differentially encoded, using a simple lookup approach. The resulting 2 bits are
convolutionally encoded, producing 3 bits. The extra bit is the redundant bit
of the trellis code. The other bits of the symbol pass by the differential
and convolutional coding unchanged. The resulting bits define the constellation
point to be transmitted for the symbol. The redundant bit doubles the size of the
constellation, and so increases the error rate for detecting individual symbols
at the receiver. However, when a number of successive symbols are processed at
the receiver, the redundancy actually provides several dB of improved error
performance.

The standard method of producing a QAM modulated signal is to use a sampling
rate which is a multiple of the baud rate. The raw signal is then a series of
complex pulses, each an integer number of samples long. These can be shaped,
using a suitable complex filter, and multiplied by a complex carrier signal
to produce the final QAM signal for transmission. 

The pulse shaping filter is only vaguely defined by the V.17 spec. Some of the
other ITU modem specs. fully define the filter, typically specifying a root
raised cosine filter, with 50% excess bandwidth. This is a pity, since it
increases the variability of the received signal. However, the receiver's
adaptive equalizer will compensate for these differences. The current
design uses a root raised cosine filter with 25% excess bandwidth. Greater
excess bandwidth will not allow the tranmitted signal to meet the spectral
requirements.

The sampling rate for our transmitter is defined by the channel - 8000 per
second. This is not a multiple of the baud rate (i.e. 2400 baud). The baud
interval is actually 10/3 sample periods. Instead of using a symmetric
FIR to pulse shape the signal, a polyphase filter is used. This consists of
10 sets of coefficients, offering zero to 9/10ths of a baud phase shift as well
as root raised cosine filtering. The appropriate coefficient set is chosen for
each signal sample generated.

The carrier is generated using the DDS method. Using two second order resonators,
started in quadrature, might be more efficient, as it would have less impact on
the processor cache than a table lookup approach. However, the DDS approach
suits the receiver better, so the same signal generator is also used for the
transmitter. 
*/

/*!
    V.17 modem transmit side descriptor. This defines the working state for a
    single instance of a V.17 modem transmitter.
*/
typedef struct v17_tx_state_s v17_tx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Adjust a V.17 modem transmit context's power output.
    \brief Adjust a V.17 modem transmit context's output power.
    \param s The modem context.
    \param power The power level, in dBm0 */
SPAN_DECLARE(void) v17_tx_power(v17_tx_state_t *s, float power);

/*! Initialise a V.17 modem transmit context. This must be called before the first
    use of the context, to initialise its contents.
    \brief Initialise a V.17 modem transmit context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 7200, 9600, 12000 and 14400.
    \param tep TRUE is the optional TEP tone is to be transmitted.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(v17_tx_state_t *) v17_tx_init(v17_tx_state_t *s, int bit_rate, int tep, get_bit_func_t get_bit, void *user_data);

/*! Reinitialise an existing V.17 modem transmit context, so it may be reused.
    \brief Reinitialise an existing V.17 modem transmit context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 7200, 9600, 12000 and 14400.
    \param tep TRUE is the optional TEP tone is to be transmitted.
    \param short_train TRUE if the short training sequence should be used.
    \return 0 for OK, -1 for parameter error. */
SPAN_DECLARE(int) v17_tx_restart(v17_tx_state_t *s, int bit_rate, int tep, int short_train);

/*! Release a V.17 modem transmit context.
    \brief Release a V.17 modem transmit context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v17_tx_release(v17_tx_state_t *s);

/*! Free a V.17 modem transmit context.
    \brief Free a V.17 modem transmit context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v17_tx_free(v17_tx_state_t *s);

/*! Get the logging context associated with a V.17 modem transmit context.
    \brief Get the logging context associated with a V.17 modem transmit context.
    \param s The modem context.
    \return A pointer to the logging context */
SPAN_DECLARE(logging_state_t *) v17_tx_get_logging_state(v17_tx_state_t *s);

/*! Change the get_bit function associated with a V.17 modem transmit context.
    \brief Change the get_bit function associated with a V.17 modem transmit context.
    \param s The modem context.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v17_tx_set_get_bit(v17_tx_state_t *s, get_bit_func_t get_bit, void *user_data);

/*! Change the modem status report function associated with a V.17 modem transmit context.
    \brief Change the modem status report function associated with a V.17 modem transmit context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v17_tx_set_modem_status_handler(v17_tx_state_t *s, modem_tx_status_func_t handler, void *user_data);

/*! Generate a block of V.17 modem audio samples.
    \brief Generate a block of V.17 modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE_NONSTD(int) v17_tx(v17_tx_state_t *s, int16_t amp[], int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
