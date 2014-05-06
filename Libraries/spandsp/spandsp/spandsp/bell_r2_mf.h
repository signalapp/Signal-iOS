/*
 * SpanDSP - a series of DSP components for telephony
 *
 * bell_r2_mf.h - Bell MF and MFC/R2 tone generation and detection.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001 Steve Underwood
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
 * $Id: bell_r2_mf.h,v 1.24 2009/02/10 13:06:47 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_BELL_R2_MF_H_)
#define _SPANDSP_BELL_R2_MF_H_

/*! \page mfc_r2_tone_generation_page MFC/R2 tone generation
\section mfc_r2_tone_generation_page_sec_1 What does it do?
The MFC/R2 tone generation module provides for the generation of the
repertoire of 15 dual tones needs for the digital MFC/R2 signalling protocol. 

\section mfc_r2_tone_generation_page_sec_2 How does it work?
*/

/*! \page bell_mf_tone_generation_page Bell MF tone generation
\section bell_mf_tone_generation_page_sec_1 What does it do?
The Bell MF tone generation module provides for the generation of the
repertoire of 15 dual tones needs for various Bell MF signalling protocols. 

\section bell_mf_tone_generation_page_sec_2 How does it work?
Basic Bell MF tone generation specs:
    - Tone on time = KP: 100+-7ms. All other signals: 68+-7ms
    - Tone off time (between digits) = 68+-7ms
    - Frequency tolerance +- 1.5%
    - Signal level -7+-1dBm per frequency
*/

/*! \page mfc_r2_tone_rx_page MFC/R2 tone receiver

\section mfc_r2_tone_rx_page_sec_1 What does it do?
The MFC/R2 tone receiver module provides for the detection of the
repertoire of 15 dual tones needs for the digital MFC/R2 signalling protocol. 
It is compliant with ITU-T Q.441D.

\section mfc_r2_tone_rx_page_sec_2 How does it work?
Basic MFC/R2 tone detection specs:
    - Receiver response range: -5dBm to -35dBm
    - Difference in level for a pair of frequencies
        - Adjacent tones: <5dB
        - Non-adjacent tones: <7dB
    - Receiver not to detect a signal of 2 frequencies of level -5dB and
      duration <7ms.
    - Receiver not to recognise a signal of 2 frequencies having a difference
      in level >=20dB.
    - Max received signal frequency error: +-10Hz
    - The sum of the operate and release times of a 2 frequency signal not to
      exceed 80ms (there are no individual specs for the operate and release
      times).
    - Receiver not to release for signal interruptions <=7ms.
    - System malfunction due to signal interruptions >7ms (typically 20ms) is
      prevented by further logic elements.
*/

/*! \page bell_mf_tone_rx_page Bell MF tone receiver

\section bell_mf_tone_rx_page_sec_1 What does it do?
The Bell MF tone receiver module provides for the detection of the
repertoire of 15 dual tones needs for various Bell MF signalling protocols. 
It is compliant with ITU-T Q.320, ITU-T Q.322, ITU-T Q.323B.

\section bell_mf_tone_rx_page_sec_2 How does it work?
Basic Bell MF tone detection specs:
    - Frequency tolerance +- 1.5% +-10Hz
    - Signal level -14dBm to 0dBm
    - Perform a "two and only two tones present" test.
    - Twist <= 6dB accepted
    - Receiver sensitive to signals above -22dBm per frequency
    - Test for a minimum of 55ms if KP, or 30ms of other signals.
    - Signals to be recognised if the two tones arrive within 8ms of each other.
    - Invalid signals result in the return of the re-order tone.

Note: Above -3dBm the signal starts to clip. We can detect with a little clipping,
      but not up to 0dBm, which the above spec seems to require. There isn't a lot
      we can do about that. Is the spec. incorrectly worded about the dBm0 reference
      point, or have I misunderstood it?
*/

/*! The maximum number of Bell MF digits we can buffer. */
#define MAX_BELL_MF_DIGITS 128

/*!
    Bell MF generator state descriptor. This defines the state of a single
    working instance of a Bell MF generator.
*/
typedef struct bell_mf_tx_state_s bell_mf_tx_state_t;

/*!
    Bell MF digit detector descriptor.
*/
typedef struct bell_mf_rx_state_s bell_mf_rx_state_t;

/*!
    MFC/R2 tone detector descriptor.
*/
typedef struct r2_mf_tx_state_s r2_mf_tx_state_t;

/*!
    MFC/R2 tone detector descriptor.
*/
typedef struct r2_mf_rx_state_s r2_mf_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Generate a buffer of Bell MF tones.
    \param s The Bell MF generator context.
    \param amp The buffer for the generated signal.
    \param max_samples The required number of generated samples.
    \return The number of samples actually generated. This may be less than 
            max_samples if the input buffer empties. */
SPAN_DECLARE(int) bell_mf_tx(bell_mf_tx_state_t *s, int16_t amp[], int max_samples);

/*! \brief Put a string of digits in a Bell MF generator's input buffer.
    \param s The Bell MF generator context.
    \param digits The string of digits to be added.
    \param len The length of the string of digits. If negative, the string is
           assumed to be a NULL terminated string.
    \return The number of digits actually added. This may be less than the
            length of the digit string, if the buffer fills up. */
SPAN_DECLARE(int) bell_mf_tx_put(bell_mf_tx_state_t *s, const char *digits, int len);

/*! \brief Initialise a Bell MF generator context.
    \param s The Bell MF generator context.
    \return A pointer to the Bell MF generator context.*/
SPAN_DECLARE(bell_mf_tx_state_t *) bell_mf_tx_init(bell_mf_tx_state_t *s);

/*! \brief Release a Bell MF generator context.
    \param s The Bell MF generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) bell_mf_tx_release(bell_mf_tx_state_t *s);

/*! \brief Free a Bell MF generator context.
    \param s The Bell MF generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) bell_mf_tx_free(bell_mf_tx_state_t *s);

/*! \brief Generate a block of R2 MF tones.
    \param s The R2 MF generator context.
    \param amp The buffer for the generated signal.
    \param samples The required number of generated samples.
    \return The number of samples actually generated. */
SPAN_DECLARE(int) r2_mf_tx(r2_mf_tx_state_t *s, int16_t amp[], int samples);

/*! \brief Generate a block of R2 MF tones.
    \param s The R2 MF generator context.
    \param digit The digit to be generated.
    \return 0 for OK, or -1 for a bad request. */
SPAN_DECLARE(int) r2_mf_tx_put(r2_mf_tx_state_t *s, char digit);

/*! \brief Initialise an R2 MF tone generator context.
    \param s The R2 MF generator context.
    \param fwd TRUE if the context is for forward signals. FALSE if the
           context is for backward signals.
    \return A pointer to the MFC/R2 generator context.*/
SPAN_DECLARE(r2_mf_tx_state_t *) r2_mf_tx_init(r2_mf_tx_state_t *s, int fwd);

/*! \brief Release an R2 MF tone generator context.
    \param s The R2 MF tone generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) r2_mf_tx_release(r2_mf_tx_state_t *s);

/*! \brief Free an R2 MF tone generator context.
    \param s The R2 MF tone generator context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) r2_mf_tx_free(r2_mf_tx_state_t *s);

/*! Process a block of received Bell MF audio samples.
    \brief Process a block of received Bell MF audio samples.
    \param s The Bell MF receiver context.
    \param amp The audio sample buffer.
    \param samples The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) bell_mf_rx(bell_mf_rx_state_t *s, const int16_t amp[], int samples);

/*! \brief Get a string of digits from a Bell MF receiver's output buffer.
    \param s The Bell MF receiver context.
    \param buf The buffer for the received digits.
    \param max The maximum  number of digits to be returned,
    \return The number of digits actually returned. */
SPAN_DECLARE(size_t) bell_mf_rx_get(bell_mf_rx_state_t *s, char *buf, int max);

/*! \brief Initialise a Bell MF receiver context.
    \param s The Bell MF receiver context.
    \param callback An optional callback routine, used to report received digits. If
           no callback routine is set, digits may be collected, using the bell_mf_rx_get()
           function.
    \param user_data An opaque pointer which is associated with the context,
           and supplied in callbacks.
    \return A pointer to the Bell MF receiver context.*/
SPAN_DECLARE(bell_mf_rx_state_t *) bell_mf_rx_init(bell_mf_rx_state_t *s,
                                                   digits_rx_callback_t callback,
                                                   void *user_data);

/*! \brief Release a Bell MF receiver context.
    \param s The Bell MF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) bell_mf_rx_release(bell_mf_rx_state_t *s);

/*! \brief Free a Bell MF receiver context.
    \param s The Bell MF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) bell_mf_rx_free(bell_mf_rx_state_t *s);

/*! Process a block of received R2 MF audio samples.
    \brief Process a block of received R2 MF audio samples.
    \param s The R2 MF receiver context.
    \param amp The audio sample buffer.
    \param samples The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) r2_mf_rx(r2_mf_rx_state_t *s, const int16_t amp[], int samples);

/*! \brief Get the current digit from an R2 MF receiver.
    \param s The R2 MF receiver context.
    \return The number digits being received. */
SPAN_DECLARE(int) r2_mf_rx_get(r2_mf_rx_state_t *s);

/*! \brief Initialise an R2 MF receiver context.
    \param s The R2 MF receiver context.
    \param fwd TRUE if the context is for forward signals. FALSE if the
           context is for backward signals.
    \param callback An optional callback routine, used to report received digits. If
           no callback routine is set, digits may be collected, using the r2_mf_rx_get()
           function.
    \param user_data An opaque pointer which is associated with the context,
           and supplied in callbacks.
    \return A pointer to the R2 MF receiver context. */
SPAN_DECLARE(r2_mf_rx_state_t *) r2_mf_rx_init(r2_mf_rx_state_t *s,
                                               int fwd,
                                               tone_report_func_t callback,
                                               void *user_data);

/*! \brief Release an R2 MF receiver context.
    \param s The R2 MF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) r2_mf_rx_release(r2_mf_rx_state_t *s);

/*! \brief Free an R2 MF receiver context.
    \param s The R2 MF receiver context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) r2_mf_rx_free(r2_mf_rx_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
