/*
 * SpanDSP - a series of DSP components for telephony
 *
 * dtmf.h - DTMF tone generation and detection.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001, 2005 Steve Underwood
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
 * $Id: dtmf.h,v 1.32 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_DTMF_H_)
#define _SPANDSP_DTMF_H_

/*! \page dtmf_rx_page DTMF receiver
\section dtmf_rx_page_sec_1 What does it do?
The DTMF receiver detects the standard DTMF digits. It is compliant with
ITU-T Q.23, ITU-T Q.24, and the local DTMF specifications of most administrations.
Its passes the test suites. It also scores *very* well on the standard
talk-off tests. 

The current design uses floating point extensively. It is not tolerant of DC.
It is expected that a DC restore stage will be placed before the DTMF detector.
Unless the dial tone filter is switched on, the detector has poor tolerance
of dial tone. Whether this matter depends on your application. If you are using
the detector in an IVR application you will need proper echo cancellation to
get good performance in the presence of speech prompts, so dial tone will not
exist. If you do need good dial tone tolerance, a dial tone filter can be
enabled in the detector.

The DTMF receiver's design assumes the channel is free of any DC component.

\section dtmf_rx_page_sec_2 How does it work?
Like most other DSP based DTMF detector's, this one uses the Goertzel algorithm
to look for the DTMF tones. What makes each detector design different is just how
that algorithm is used.

Basic DTMF specs:
    - Minimum tone on = 40ms
    - Minimum tone off = 50ms
    - Maximum digit rate = 10 per second
    - Normal twist <= 8dB accepted
    - Reverse twist <= 4dB accepted
    - S/N >= 15dB will detect OK
    - Attenuation <= 26dB will detect OK
    - Frequency tolerance +- 1.5% will detect, +-3.5% will reject

TODO:
*/

/*! \page dtmf_tx_page DTMF tone generation
\section dtmf_tx_page_sec_1 What does it do?

The DTMF tone generation module provides for the generation of the
repertoire of 16 DTMF dual tones. 

\section dtmf_tx_page_sec_2 How does it work?
*/

#define MAX_DTMF_DIGITS 128

typedef void (*digits_rx_callback_t)(void *user_data, const char *digits, int len);

/*!
    DTMF generator state descriptor. This defines the state of a single
    working instance of a DTMF generator.
*/
typedef struct dtmf_tx_state_s dtmf_tx_state_t;

/*!
    DTMF digit detector descriptor.
*/
typedef struct dtmf_rx_state_s dtmf_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Generate a buffer of DTMF tones.
    \param s The DTMF generator context.
    \param amp The buffer for the generated signal.
    \param max_samples The required number of generated samples.
    \return The number of samples actually generated. This may be less than 
            max_samples if the input buffer empties. */
SPAN_DECLARE(int) dtmf_tx(dtmf_tx_state_t *s, int16_t amp[], int max_samples);

/*! \brief Put a string of digits in a DTMF generator's input buffer.
    \param s The DTMF generator context.
    \param digits The string of digits to be added.
    \param len The length of the string of digits. If negative, the string is
           assumed to be a NULL terminated string.
    \return The number of digits actually added. This may be less than the
            length of the digit string, if the buffer fills up. */
SPAN_DECLARE(int) dtmf_tx_put(dtmf_tx_state_t *s, const char *digits, int len);

/*! \brief Change the transmit level for a DTMF tone generator context.
    \param s The DTMF generator context.
    \param level The level of the low tone, in dBm0.
    \param twist The twist, in dB. */
SPAN_DECLARE(void) dtmf_tx_set_level(dtmf_tx_state_t *s, int level, int twist);

/*! \brief Change the transmit on and off time for a DTMF tone generator context.
    \param s The DTMF generator context.
    \param on-time The on time, in ms.
    \param off_time The off time, in ms. */
SPAN_DECLARE(void) dtmf_tx_set_timing(dtmf_tx_state_t *s, int on_time, int off_time);

/*! \brief Initialise a DTMF tone generator context.
    \param s The DTMF generator context.
    \return A pointer to the DTMF generator context. */
SPAN_DECLARE(dtmf_tx_state_t *) dtmf_tx_init(dtmf_tx_state_t *s);

/*! \brief Release a DTMF tone generator context.
    \param s The DTMF tone generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) dtmf_tx_release(dtmf_tx_state_t *s);

/*! \brief Free a DTMF tone generator context.
    \param s The DTMF tone generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) dtmf_tx_free(dtmf_tx_state_t *s);

/*! Set a optional realtime callback for a DTMF receiver context. This function
    is called immediately a confirmed state change occurs in the received DTMF. It
    is called with the ASCII value for a DTMF tone pair, or zero to indicate no tone
    is being received.
    \brief Set a realtime callback for a DTMF receiver context.
    \param s The DTMF receiver context.
    \param callback Callback routine used to report the start and end of digits.
    \param user_data An opaque pointer which is associated with the context,
           and supplied in callbacks. */
SPAN_DECLARE(void) dtmf_rx_set_realtime_callback(dtmf_rx_state_t *s,
                                                 tone_report_func_t callback,
                                                 void *user_data);

/*! \brief Adjust a DTMF receiver context.
    \param s The DTMF receiver context.
    \param filter_dialtone TRUE to enable filtering of dialtone, FALSE
           to disable, < 0 to leave unchanged.
    \param twist Acceptable twist, in dB. < 0 to leave unchanged.
    \param reverse_twist Acceptable reverse twist, in dB. < 0 to leave unchanged.
    \param threshold The minimum acceptable tone level for detection, in dBm0.
           <= -99 to leave unchanged. */
SPAN_DECLARE(void) dtmf_rx_parms(dtmf_rx_state_t *s,
                                 int filter_dialtone,
                                 int twist,
                                 int reverse_twist,
                                 int threshold);

/*! Process a block of received DTMF audio samples.
    \brief Process a block of received DTMF audio samples.
    \param s The DTMF receiver context.
    \param amp The audio sample buffer.
    \param samples The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) dtmf_rx(dtmf_rx_state_t *s, const int16_t amp[], int samples);

/*! Get the status of DTMF detection during processing of the last audio
    chunk.
    \brief Get the status of DTMF detection during processing of the last
           audio chunk.
    \param s The DTMF receiver context.
    \return The current digit status. Either 'x' for a "maybe" condition, or the
            digit being detected. */
SPAN_DECLARE(int) dtmf_rx_status(dtmf_rx_state_t *s);

/*! \brief Get a string of digits from a DTMF receiver's output buffer.
    \param s The DTMF receiver context.
    \param digits The buffer for the received digits.
    \param max The maximum  number of digits to be returned,
    \return The number of digits actually returned. */
SPAN_DECLARE(size_t) dtmf_rx_get(dtmf_rx_state_t *s, char *digits, int max);

/*! \brief Initialise a DTMF receiver context.
    \param s The DTMF receiver context.
    \param callback An optional callback routine, used to report received digits. If
           no callback routine is set, digits may be collected, using the dtmf_rx_get()
           function.
    \param user_data An opaque pointer which is associated with the context,
           and supplied in callbacks.
    \return A pointer to the DTMF receiver context. */
SPAN_DECLARE(dtmf_rx_state_t *) dtmf_rx_init(dtmf_rx_state_t *s,
                                             digits_rx_callback_t callback,
                                             void *user_data);

/*! \brief Release a DTMF receiver context.
    \param s The DTMF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) dtmf_rx_release(dtmf_rx_state_t *s);

/*! \brief Free a DTMF receiver context.
    \param s The DTMF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) dtmf_rx_free(dtmf_rx_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
