/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t38_terminal.h - T.38 termination, less the packet exchange part
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005 Steve Underwood
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
 * $Id: t38_terminal.h,v 1.41 2009/02/03 16:28:41 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T38_TERMINAL_H_)
#define _SPANDSP_T38_TERMINAL_H_

/*! \page t38_terminal_page T.38 real time FAX over IP termination
\section t38_terminal_page_sec_1 What does it do?

\section t38_terminal_page_sec_2 How does it work?
*/

/* Make sure the HDLC frame buffers are big enough for ECM frames. */
#define T38_MAX_HDLC_LEN        260

typedef struct t38_terminal_state_s t38_terminal_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(int) t38_terminal_send_timeout(t38_terminal_state_t *s, int samples);

SPAN_DECLARE(void) t38_terminal_set_config(t38_terminal_state_t *s, int without_pacing);

/*! Select whether the time for talker echo protection tone will be allowed for when sending.
    \brief Select whether TEP time will be allowed for.
    \param s The T.38 context.
    \param use_tep TRUE if TEP should be allowed for.
*/
SPAN_DECLARE(void) t38_terminal_set_tep_mode(t38_terminal_state_t *s, int use_tep);

/*! Select whether non-ECM fill bits are to be removed during transmission.
    \brief Select whether non-ECM fill bits are to be removed during transmission.
    \param s The T.38 context.
    \param remove TRUE if fill bits are to be removed.
*/
SPAN_DECLARE(void) t38_terminal_set_fill_bit_removal(t38_terminal_state_t *s, int remove);

/*! Get a pointer to the T.30 engine associated with a termination mode T.38 context.
    \brief Get a pointer to the T.30 engine associated with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the T.30 context, or NULL.
*/
SPAN_DECLARE(t30_state_t *) t38_terminal_get_t30_state(t38_terminal_state_t *s);

/*! Get a pointer to the T.38 core IFP packet engine associated with a
    termination mode T.38 context.
    \brief Get a pointer to the T.38 core IFP packet engine associated
           with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the T.38 core context, or NULL.
*/
SPAN_DECLARE(t38_core_state_t *) t38_terminal_get_t38_core_state(t38_terminal_state_t *s);

/*! Get a pointer to the logging context associated with a T.38 context.
    \brief Get a pointer to the logging context associated with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the logging context, or NULL.
*/
SPAN_DECLARE(logging_state_t *) t38_terminal_get_logging_state(t38_terminal_state_t *s);

/*! \brief Initialise a termination mode T.38 context.
    \param s The T.38 context.
    \param calling_party TRUE if the context is for a calling party. FALSE if the
           context is for an answering party.
    \param tx_packet_handler A callback routine to encapsulate and transmit T.38 packets.
    \param tx_packet_user_data An opaque pointer passed to the tx_packet_handler routine.
    \return A pointer to the termination mode T.38 context, or NULL if there was a problem. */
SPAN_DECLARE(t38_terminal_state_t *) t38_terminal_init(t38_terminal_state_t *s,
                                                       int calling_party,
                                                       t38_tx_packet_handler_t *tx_packet_handler,
                                                       void *tx_packet_user_data);

/*! Release a termination mode T.38 context.
    \brief Release a T.38 context.
    \param s The T.38 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t38_terminal_release(t38_terminal_state_t *s);

/*! Free a a termination mode T.38 context.
    \brief Free a T.38 context.
    \param s The T.38 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t38_terminal_free(t38_terminal_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
