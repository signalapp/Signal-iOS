/*
 * SpanDSP - a series of DSP components for telephony
 *
 * silence_gen.c - A silence generator, for inserting timed silences.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2006 Steve Underwood
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
 * $Id: silence_gen.h,v 1.19 2009/09/04 14:38:47 steveu Exp $
 */

#if !defined(_SPANDSP_SILENCE_GEN_H_)
#define _SPANDSP_SILENCE_GEN_H_

typedef struct silence_gen_state_s silence_gen_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Generate a block of silent audio samples.
    \brief Generate a block of silent audio samples.
    \param s The silence generator context.
    \param amp The audio sample buffer.
    \param max_len The number of samples to be generated.
    \return The number of samples actually generated. This will be zero when
            there is nothing to send.
*/
SPAN_DECLARE_NONSTD(int) silence_gen(silence_gen_state_t *s, int16_t *amp, int max_len);

/*! Set a silence generator context to output continuous silence.
    \brief Set a silence generator context to output continuous silence.
    \param s The silence generator context.
*/
SPAN_DECLARE(void) silence_gen_always(silence_gen_state_t *s);

/*! Set a silence generator context to output a specified period of silence.
    \brief Set a silence generator context to output a specified period of silence.
    \param s The silence generator context.
    \param silent_samples The number of samples to be generated.
*/
SPAN_DECLARE(void) silence_gen_set(silence_gen_state_t *s, int silent_samples);

/*! Alter the period of a silence generator context by a specified amount.
    \brief Alter the period of a silence generator context by a specified amount.
    \param s The silence generator context.
    \param silent_samples The number of samples to change the setting by. A positive number
                          increases the duration. A negative number reduces it. The duration
                          is prevented from going negative.
*/
SPAN_DECLARE(void) silence_gen_alter(silence_gen_state_t *s, int silent_samples);

/*! Find how long a silence generator context has to run.
    \brief Find how long a silence generator context has to run.
    \param s The silence generator context.
    \return The number of samples remaining.
*/
SPAN_DECLARE(int) silence_gen_remainder(silence_gen_state_t *s);

/*! Find the total silence generated to date by a silence generator context.
    \brief Find the total silence generated to date.
    \param s The silence generator context.
    \return The number of samples generated.
*/
SPAN_DECLARE(int) silence_gen_generated(silence_gen_state_t *s);

/*! Change the status reporting function associated with a silence generator context.
    \brief Change the status reporting function associated with a silence generator context.
    \param s The silence generator context.
    \param handler The callback routine used to report status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) silence_gen_status_handler(silence_gen_state_t *s, modem_tx_status_func_t handler, void *user_data);

/*! Initialise a timed silence generator context.
    \brief Initialise a timed silence generator context.
    \param s The silence generator context.
    \param silent_samples The initial number of samples to set the silence to.
    \return A pointer to the silence generator context.
*/
SPAN_DECLARE(silence_gen_state_t *) silence_gen_init(silence_gen_state_t *s, int silent_samples);

SPAN_DECLARE(int) silence_gen_release(silence_gen_state_t *s);

SPAN_DECLARE(int) silence_gen_free(silence_gen_state_t *s);

/* The following dummy routines, to absorb data, don't really have a proper home,
   so they have been put here. */

/*! A dummy routine to use as a receive callback, when we aren't really
    trying to process what is received. It just absorbs and ignores the
    data.
    \brief Dummy receive callback.
    \param user_data The context.
    \param amp The signal.buffer
    \param len The length of the signal buffer
    \return 0.
*/
SPAN_DECLARE_NONSTD(int) span_dummy_rx(void *user_data, const int16_t amp[], int len);

/*! A dummy routine to use as a signal modifier callback, when we aren't
    really trying to process the signal. It just returns without affecting
    anything.
    \brief Dummy signal modifier callback.
    \param user_data The context.
    \param amp The signal.buffer
    \param len The length of the signal buffer
    \return 0.
*/
SPAN_DECLARE(int) span_dummy_mod(void *user_data, int16_t amp[], int len);

/*! A dummy routine to use as a receive fillin callback, when we aren't really
    trying to process what is received. It just absorbs and ignores the
    request.
    \brief Dummy receive fillin callback.
    \param user_data The context.
    \param len The length of the signal buffer
    \return 0.
*/
SPAN_DECLARE_NONSTD(int) span_dummy_rx_fillin(void *user_data, int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
