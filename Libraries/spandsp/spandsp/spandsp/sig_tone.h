/*
 * SpanDSP - a series of DSP components for telephony
 *
 * sig_tone.h - Signalling tone processing for the 2280Hz, 2400Hz, 2600Hz
 *              and similar signalling tone used in older protocols.
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
 * $Id: sig_tone.h,v 1.20 2009/09/04 14:38:46 steveu Exp $
 */

/*! \file */

/*! \page sig_tone_page The signaling tone processor
\section sig_tone_sec_1 What does it do?
The signaling tone processor handles the 2280Hz, 2400Hz and 2600Hz tones, used
in many analogue signaling procotols, and digital ones derived from them.

\section sig_tone_sec_2 How does it work?
Most single and two voice frequency signalling systems share many features, as these
features have developed in similar ways over time, to address the limitations of
early tone signalling systems.

The usual practice is to start the generation of tone at a high energy level, so a
strong signal is available at the receiver, for crisp tone detection. If the tone
remains on for a significant period, the energy level is reduced, to minimise crosstalk.
During the signalling transitions, only the tone is sent through the channel, and the media
signal is suppressed. This means the signalling receiver has a very clean signal to work with,
allowing for crisp detection of the signalling tone. However, when the signalling tone is on
for extended periods, there may be supervisory information in the media signal, such as voice
announcements. To allow these to pass through the system, the signalling tone is mixed with
the media signal. It is the job of the signalling receiver to separate the signalling tone
and the media. The necessary filtering may degrade the quality of the voice signal, but at
least supervisory information may be heard.
*/

#if !defined(_SPANDSP_SIG_TONE_H_)
#define _SPANDSP_SIG_TONE_H_

/* The optional tone sets */
enum
{
    /*! European 2280Hz signaling tone. Tone 1 is 2280Hz. Tone 2 is not used. */
    SIG_TONE_2280HZ = 1,
    /*! US 2600Hz signaling tone. Tone 1 is 2600Hz. Tone 2 is not used. */
    SIG_TONE_2600HZ,
    /*! US 2400Hz + 2600Hz signaling tones. Tone 1 is 2600Hz. Tone 2 is 2400Hz. */
    SIG_TONE_2400HZ_2600HZ
};

/* Mode control and report bits for transmit and receive */
enum
{
    /*! Signaling tone 1 is present */
    SIG_TONE_1_PRESENT          = 0x001,
    /*! Signaling tone 1 has changed state (ignored when setting tx mode) */
    SIG_TONE_1_CHANGE           = 0x002,
    /*! Signaling tone 2 is present */
    SIG_TONE_2_PRESENT          = 0x004,
    /*! Signaling tone 2 has changed state (ignored when setting tx mode) */
    SIG_TONE_2_CHANGE           = 0x008,
    /*! The media signal is passing through. Tones might be added to it. */
    SIG_TONE_TX_PASSTHROUGH     = 0x010,
    /*! The media signal is passing through. Tones might be extracted from it, if detected. */
    SIG_TONE_RX_PASSTHROUGH     = 0x040,
    /*! Force filtering of the signaling tone, whether signaling is being detected or not.
        This is mostly useful for test purposes. */
    SIG_TONE_RX_FILTER_TONE     = 0x080,
    /*! Request an update of the transmit status, upon timeout of the previous status. */
    SIG_TONE_TX_UPDATE_REQUEST  = 0x100,
    /*! Request an update of the receiver status, upon timeout of the previous status. */
    SIG_TONE_RX_UPDATE_REQUEST  = 0x200
};

/*!
    Signaling tone descriptor. This defines the working state for a
    single instance of the transmit and receive sides of a signaling
    tone processor.
*/
typedef struct sig_tone_descriptor_s sig_tone_descriptor_t;

typedef struct sig_tone_tx_state_s sig_tone_tx_state_t;

typedef struct sig_tone_rx_state_s sig_tone_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Process a block of received audio samples.
    \brief Process a block of received audio samples.
    \param s The signaling tone context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) sig_tone_rx(sig_tone_rx_state_t *s, int16_t amp[], int len);

/*! Set the receive mode.
    \brief Set the receive mode.
    \param s The signaling tone context.
    \param mode The new mode for the receiver.
    \param duration The duration for this mode, before an update is requested.
                    A duration of zero means forever. */
SPAN_DECLARE(void) sig_tone_rx_set_mode(sig_tone_rx_state_t *s, int mode, int duration);

/*! Initialise a signaling tone receiver context.
    \brief Initialise a signaling tone context.
    \param s The signaling tone context.
    \param tone_type The type of signaling tone.
    \param sig_update Callback function to handle signaling updates.
    \param user_data An opaque pointer.
    \return A pointer to the signalling tone context, or NULL if there was a problem. */
SPAN_DECLARE(sig_tone_rx_state_t *) sig_tone_rx_init(sig_tone_rx_state_t *s, int tone_type, tone_report_func_t sig_update, void *user_data);

/*! Release a signaling tone receiver context.
    \brief Release a signaling tone receiver context.
    \param s The signaling tone context.
    \return 0 for OK */
SPAN_DECLARE(int) sig_tone_rx_release(sig_tone_rx_state_t *s);

/*! Free a signaling tone receiver context.
    \brief Free a signaling tone receiver context.
    \param s The signaling tone context.
    \return 0 for OK */
SPAN_DECLARE(int) sig_tone_rx_free(sig_tone_rx_state_t *s);

/*! Generate a block of signaling tone audio samples.
    \brief Generate a block of signaling tone audio samples.
    \param s The signaling tone context.
    \param amp The audio sample buffer.
    \param len The number of samples to be generated.
    \return The number of samples actually generated. */
SPAN_DECLARE(int) sig_tone_tx(sig_tone_tx_state_t *s, int16_t amp[], int len);

/*! Set the tone mode.
    \brief Set the tone mode.
    \param s The signaling tone context.
    \param mode The new mode for the transmitted tones.
    \param duration The duration for this mode, before an update is requested.
                    A duration of zero means forever. */
SPAN_DECLARE(void) sig_tone_tx_set_mode(sig_tone_tx_state_t *s, int mode, int duration);

/*! Initialise a signaling tone transmitter context.
    \brief Initialise a signaling tone context.
    \param s The signaling tone context.
    \param tone_type The type of signaling tone.
    \param sig_update Callback function to handle signaling updates.
    \param user_data An opaque pointer.
    \return A pointer to the signalling tone context, or NULL if there was a problem. */
SPAN_DECLARE(sig_tone_tx_state_t *) sig_tone_tx_init(sig_tone_tx_state_t *s, int tone_type, tone_report_func_t sig_update, void *user_data);

/*! Release a signaling tone transmitter context.
    \brief Release a signaling tone transmitter context.
    \param s The signaling tone context.
    \return 0 for OK */
SPAN_DECLARE(int) sig_tone_tx_release(sig_tone_tx_state_t *s);

/*! Free a signaling tone transmitter context.
    \brief Free a signaling tone transmitter context.
    \param s The signaling tone context.
    \return 0 for OK */
SPAN_DECLARE(int) sig_tone_tx_free(sig_tone_tx_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
