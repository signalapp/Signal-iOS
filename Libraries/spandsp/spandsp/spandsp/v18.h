/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v18.h - V.18 text telephony for the deaf.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004-2009 Steve Underwood
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
 * $Id: v18.h,v 1.6 2009/11/04 15:52:06 steveu Exp $
 */
 
/*! \file */

/*! \page v18_page The V.18 text telephony protocols
\section v18_page_sec_1 What does it do?

\section v18_page_sec_2 How does it work?
*/

#if !defined(_SPANDSP_V18_H_)
#define _SPANDSP_V18_H_

typedef struct v18_state_s v18_state_t;

enum
{
    V18_MODE_NONE = 0,
    /* V.18 Annex A - Weitbrecht TDD at 45.45bps, half-duplex, 5 bit baudot. */
    V18_MODE_5BIT_45 = 1,
    /* V.18 Annex A - Weitbrecht TDD at 50bps, half-duplex, 5 bit baudot. */
    V18_MODE_5BIT_50 = 2,
    /* V.18 Annex B - DTMF encoding of ASCII. */
    V18_MODE_DTMF = 3,
    /* V.18 Annex C - EDT 110bps, V.21, half-duplex, ASCII. */
    V18_MODE_EDT = 4,
    /* V.18 Annex D - 300bps, Bell 103, duplex, ASCII. */
    V18_MODE_BELL103 = 5,
    /* V.18 Annex E - 1200bps Videotex terminals, ASCII. */
    V18_MODE_V23VIDEOTEX = 6,
    /* V.18 Annex F - V.21 text telephone, V.21, duplex, ASCII. */
    V18_MODE_V21TEXTPHONE = 7,
    /* V.18 Annex G - V.18 text telephone mode. */
    V18_MODE_V18TEXTPHONE = 8
};

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(logging_state_t *) v18_get_logging_state(v18_state_t *s);

/*! Initialise a V.18 context.
    \brief Initialise a V.18 context.
    \param s The V.18 context.
    \param calling_party TRUE if caller mode, else answerer mode.
    \param mode Mode of operation.
    \param put_msg A callback routine called to deliver the received text
           to the application.
    \param user_data An opaque pointer for the callback routine.
    \return A pointer to the V.18 context, or NULL if there was a problem. */
SPAN_DECLARE(v18_state_t *) v18_init(v18_state_t *s,
                                     int calling_party,
                                     int mode,
                                     put_msg_func_t put_msg,
                                     void *user_data);

/*! Release a V.18 context.
    \brief Release a V.18 context.
    \param s The V.18 context.
    \return 0 for OK. */
SPAN_DECLARE(int) v18_release(v18_state_t *s);

/*! Free a V.18 context.
    \brief Release a V.18 context.
    \param s The V.18 context.
    \return 0 for OK. */
SPAN_DECLARE(int) v18_free(v18_state_t *s);

/*! Generate a block of V.18 audio samples.
    \brief Generate a block of V.18 audio samples.
    \param s The V.18 context.
    \param amp The audio sample buffer.
    \param max_len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE_NONSTD(int) v18_tx(v18_state_t *s, int16_t amp[], int max_len);

/*! Process a block of received V.18 audio samples.
    \brief Process a block of received V.18 audio samples.
    \param s The V.18 context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
*/
SPAN_DECLARE_NONSTD(int) v18_rx(v18_state_t *s, const int16_t amp[], int len);

/*! \brief Put a string to a V.18 context's input buffer.
    \param s The V.18 context.
    \param msg The string to be added.
    \param len The length of the string. If negative, the string is
           assumed to be a NULL terminated string.
    \return The number of characters actually added. This may be less than the
            length of the digit string, if the buffer fills up. If the string is
            invalid, this function will return -1. */
SPAN_DECLARE(int) v18_put(v18_state_t *s, const char msg[], int len);

/*! Convert a text string to a V.18 DTMF string.
    \brief Convert a text string to a V.18 DTMF string.
    \param s The V.18 context.
    \param dtmf The resulting DTMF string.
    \param msg The text string to be converted.
    \return The length of the DTMF string.
*/
SPAN_DECLARE(int) v18_encode_dtmf(v18_state_t *s, char dtmf[], const char msg[]);

/*! Convert a V.18 DTMF string to a text string.
    \brief Convert a V.18 DTMF string to a text string.
    \param s The V.18 context.
    \param msg The resulting test string.
    \param dtmf The DTMF string to be converted.
    \return The length of the text string.
*/
SPAN_DECLARE(int) v18_decode_dtmf(v18_state_t *s, char msg[], const char dtmf[]);

SPAN_DECLARE(uint16_t) v18_encode_baudot(v18_state_t *s, uint8_t ch);

SPAN_DECLARE(uint8_t) v18_decode_baudot(v18_state_t *s, uint8_t ch);

/*! \brief Return a short name for an V.18 mode
    \param mode The code for the V.18 mode.
    \return A pointer to the name.
*/
SPAN_DECLARE(const char *) v18_mode_to_str(int mode);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
