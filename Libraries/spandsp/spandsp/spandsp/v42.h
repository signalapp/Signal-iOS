/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v42.h
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
 * $Id: v42.h,v 1.31 2009/11/04 15:52:06 steveu Exp $
 */

/*! \page v42_page V.42 modem error correction
\section v42_page_sec_1 What does it do?
The V.42 specification defines an error correcting protocol for PSTN modems, based on
HDLC and LAP. This makes it similar to an X.25 link. A special variant of LAP, known
as LAP-M, is defined in the V.42 specification. A means for modems to determine if the
far modem supports V.42 is also defined.

\section v42_page_sec_2 How does it work?
*/

#if !defined(_SPANDSP_V42_H_)
#define _SPANDSP_V42_H_

enum
{
    LAPM_DETECT = 0,
    LAPM_ESTABLISH = 1,
    LAPM_DATA = 2,
    LAPM_RELEASE = 3,
    LAPM_SIGNAL = 4,
    LAPM_SETPARM = 5,
    LAPM_TEST = 6,
    LAPM_UNSUPPORTED = 7
};

typedef void (*v42_status_func_t)(void *user_data, int status);
typedef void (*v42_frame_handler_t)(void *user_data, const uint8_t *pkt, int len);

typedef struct lapm_frame_queue_s
{
    struct lapm_frame_queue_s *next;
    int len;
    uint8_t frame[];
} lapm_frame_queue_t;

/*!
    LAP-M descriptor. This defines the working state for a single instance of LAP-M.
*/
typedef struct lapm_state_s lapm_state_t;

/*!
    V.42 descriptor. This defines the working state for a single instance of V.42.
*/
typedef struct v42_state_s v42_state_t;

/*! Log the raw HDLC frames */
#define LAPM_DEBUG_LAPM_RAW         (1 << 0)
/*! Log the interpreted frames */
#define LAPM_DEBUG_LAPM_DUMP        (1 << 1)
/*! Log state machine changes */
#define LAPM_DEBUG_LAPM_STATE 	    (1 << 2)

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(const char *) lapm_status_to_str(int status);

/*! Dump LAP.M frames in a raw and/or decoded forms
    \param frame The frame itself
    \param len The length of the frame, in octets
    \param showraw TRUE if the raw octets should be dumped
    \param txrx TRUE if tx, FALSE if rx. Used to highlight the packet's direction.
*/
SPAN_DECLARE(void) lapm_dump(lapm_state_t *s, const uint8_t *frame, int len, int showraw, int txrx);

/*! Accept an HDLC packet
*/
SPAN_DECLARE_NONSTD(void) lapm_receive(void *user_data, const uint8_t *buf, int len, int ok);

/*! Transmit a LAP.M frame
*/
SPAN_DECLARE(int) lapm_tx(lapm_state_t *s, const void *buf, int len);

/*! Transmit a LAP.M information frame
*/
SPAN_DECLARE(int) lapm_tx_iframe(lapm_state_t *s, const void *buf, int len, int cr);

/*! Send a break over a LAP.M connection
*/
SPAN_DECLARE(int) lapm_break(lapm_state_t *s, int enable);

/*! Initiate an orderly release of a LAP.M connection
*/
SPAN_DECLARE(int) lapm_release(lapm_state_t *s);

/*! Enable or disable loopback of a LAP.M connection
*/
SPAN_DECLARE(int) lapm_loopback(lapm_state_t *s, int enable);

/*! Assign or remove a callback routine used to deal with V.42 status changes.
*/
SPAN_DECLARE(void) v42_set_status_callback(v42_state_t *s, v42_status_func_t callback, void *user_data);

/*! Process a newly received bit for a V.42 context.
*/
SPAN_DECLARE(void) v42_rx_bit(void *user_data, int bit);

/*! Get the next transmit bit for a V.42 context.
*/
SPAN_DECLARE(int) v42_tx_bit(void *user_data);

/*! Initialise a V.42 context.
    \param s The V.42 context.
    \param calling_party TRUE if caller mode, else answerer mode.
    \param frame_handler A callback function to handle received frames of data.
    \param user_data An opaque pointer passed to the frame handler routine.
    \return ???
*/
SPAN_DECLARE(v42_state_t *) v42_init(v42_state_t *s, int calling_party, int detect, v42_frame_handler_t frame_handler, void *user_data);

/*! Restart a V.42 context.
    \param s The V.42 context.
*/
SPAN_DECLARE(void) v42_restart(v42_state_t *s);

/*! Release a V.42 context.
    \param s The V.42 context.
    \return 0 if OK */
SPAN_DECLARE(int) v42_release(v42_state_t *s);

/*! Free a V.42 context.
    \param s The V.42 context.
    \return 0 if OK */
SPAN_DECLARE(int) v42_free(v42_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
