/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v29tx.h - ITU V.29 modem transmit part
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
 * $Id: v29tx.h,v 1.41 2009/07/09 13:52:09 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_V29TX_H_)
#define _SPANDSP_V29TX_H_

/*! \page v29tx_page The V.29 transmitter
\section v29tx_page_sec_1 What does it do?
The V.29 transmitter implements the transmit side of a V.29 modem. This can
operate at data rates of 9600, 7200 and 4800 bits/s. The audio output is a
stream of 16 bit samples, at 8000 samples/second. The transmit and receive side
of V.29 modems operate independantly. V.29 is mostly used for FAX transmission,
where it provides the standard 9600 and 7200 bits/s rates (the 4800 bits/s mode
is not used for FAX). 

\section v29tx_page_sec_2 How does it work?
V.29 uses QAM modulation. The standard method of producing a QAM modulated
signal is to use a sampling rate which is a multiple of the baud rate. The raw
signal is then a series of complex pulses, each an integer number of samples
long. These can be shaped, using a suitable complex filter, and multiplied by a
complex carrier signal to produce the final QAM signal for transmission. 

The pulse shaping filter is only vaguely defined by the V.29 spec. Some of the
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

The equation defining QAM modulation is:

    s(n) = A*cos(2*pi*f*n + phi(n))

where phi(n) is the phase of the information, and A is the amplitude of the information

using the identity

    cos(x + y) = cos(x)*cos(y) - sin(x)*sin(y)
    
we get

    s(n) = A {cos(2*pi*f*n)*cos(phi(n)) - sin(2*pi*f*n)*sin(phi(n))}
    
substituting with the constellation positions

    I(n) = A*cos(phi(n))
    Q(n) = A*sin(phi(n))
    
gives

    s(n) = I(n)*cos(2*pi*f*n) - Q(n)*sin(2*pi*f*n)

*/

/*!
    V.29 modem transmit side descriptor. This defines the working state for a
    single instance of a V.29 modem transmitter.
*/
typedef struct v29_tx_state_s v29_tx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Adjust a V.29 modem transmit context's power output.
    \brief Adjust a V.29 modem transmit context's output power.
    \param s The modem context.
    \param power The power level, in dBm0 */
SPAN_DECLARE(void) v29_tx_power(v29_tx_state_t *s, float power);

/*! Initialise a V.29 modem transmit context. This must be called before the first
    use of the context, to initialise its contents.
    \brief Initialise a V.29 modem transmit context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 4800, 7200 and 9600.
    \param tep TRUE is the optional TEP tone is to be transmitted.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(v29_tx_state_t *) v29_tx_init(v29_tx_state_t *s, int bit_rate, int tep, get_bit_func_t get_bit, void *user_data);

/*! Reinitialise an existing V.29 modem transmit context, so it may be reused.
    \brief Reinitialise an existing V.29 modem transmit context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 4800, 7200 and 9600.
    \param tep TRUE is the optional TEP tone is to be transmitted.
    \return 0 for OK, -1 for bad parameter */
SPAN_DECLARE(int) v29_tx_restart(v29_tx_state_t *s, int bit_rate, int tep);

/*! Release a V.29 modem transmit context.
    \brief Release a V.29 modem transmit context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v29_tx_release(v29_tx_state_t *s);

/*! Free a V.29 modem transmit context.
    \brief Free a V.29 modem transmit context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v29_tx_free(v29_tx_state_t *s);

/*! Get the logging context associated with a V.29 modem transmit context.
    \brief Get the logging context associated with a V.29 modem transmit context.
    \param s The modem context.
    \return A pointer to the logging context */
SPAN_DECLARE(logging_state_t *) v29_tx_get_logging_state(v29_tx_state_t *s);

/*! Change the get_bit function associated with a V.29 modem transmit context.
    \brief Change the get_bit function associated with a V.29 modem transmit context.
    \param s The modem context.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v29_tx_set_get_bit(v29_tx_state_t *s, get_bit_func_t get_bit, void *user_data);

/*! Change the modem status report function associated with a V.29 modem transmit context.
    \brief Change the modem status report function associated with a V.29 modem transmit context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v29_tx_set_modem_status_handler(v29_tx_state_t *s, modem_tx_status_func_t handler, void *user_data);

/*! Generate a block of V.29 modem audio samples.
    \brief Generate a block of V.29 modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE_NONSTD(int) v29_tx(v29_tx_state_t *s, int16_t amp[], int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
