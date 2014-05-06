/*
 * SpanDSP - a series of DSP components for telephony
 *
 * modem_echo.h - An echo cancellor, suitable for electrical echos in GSTN modems
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001, 2004 Steve Underwood
 *
 * Based on a bit from here, a bit from there, eye of toad,
 * ear of bat, etc - plus, of course, my own 2 cents.
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
 * $Id: modem_echo.h,v 1.14 2009/09/22 13:11:04 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_MODEM_ECHO_H_)
#define _SPANDSP_MODEM_ECHO_H_

/*! \page modem_echo_can_page Line echo cancellation for modems

\section modem_echo_can_page_sec_1 What does it do?
This module aims to cancel electrical echoes (e.g. from 2-4 wire hybrids)
in modem applications. It is not very suitable for speech applications, which
require additional refinements for satisfactory performance. It is, however, more
efficient and better suited to modem applications. 

\section modem_echo_can_page_sec_2 How does it work?
The heart of the echo cancellor is an adaptive FIR filter. This is adapted to
match the impulse response of the environment being cancelled. It must be long
enough to adequately cover the duration of that impulse response. The signal
being transmitted into the environment being cancelled is passed through the
FIR filter. The resulting output is an estimate of the echo signal. This is
then subtracted from the received signal, and the result should be an estimate
of the signal which originates within the environment being cancelled (people
talking in the room, or the signal from the far end of a telephone line) free
from the echos of our own transmitted signal. 

The FIR filter is adapted using the least mean squares (LMS) algorithm. This
algorithm is attributed to Widrow and Hoff, and was introduced in 1960. It is
the commonest form of filter adaption used in things like modem line equalisers
and line echo cancellers. It works very well if the signal level is constant,
which is true for a modem signal. To ensure good performa certain conditions must
be met: 

    - The transmitted signal has weak self-correlation.
    - There is no signal being generated within the environment being cancelled.

The difficulty is that neither of these can be guaranteed. If the adaption is
performed while transmitting noise (or something fairly noise like, such as
voice) the adaption works very well. If the adaption is performed while
transmitting something highly correlative (e.g. tones, like DTMF), the adaption
can go seriously wrong. The reason is there is only one solution for the
adaption on a near random signal. For a repetitive signal, there are a number of
solutions which converge the adaption, and nothing guides the adaption to choose
the correct one. 

\section modem_echo_can_page_sec_3 How do I use it?
The echo cancellor processes both the transmit and receive streams sample by
sample. The processing function is not declared inline. Unfortunately,
cancellation requires many operations per sample, so the call overhead is only a
minor burden. 
*/

#include "fir.h"

/*!
    Modem line echo canceller descriptor. This defines the working state for a line
    echo canceller.
*/
typedef struct modem_echo_can_state_s modem_echo_can_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Create a modem echo canceller context.
    \param len The length of the canceller, in samples.
    eturn The new canceller context, or NULL if the canceller could not be created.
*/
SPAN_DECLARE(modem_echo_can_state_t *) modem_echo_can_create(int len);

/*! Free a modem echo canceller context.
    \param ec The echo canceller context.
*/
SPAN_DECLARE(void) modem_echo_can_free(modem_echo_can_state_t *ec);

/*! Flush (reinitialise) a modem echo canceller context.
    \param ec The echo canceller context.
*/
SPAN_DECLARE(void) modem_echo_can_flush(modem_echo_can_state_t *ec);

/*! Set the adaption mode of a modem echo canceller context.
    \param ec The echo canceller context.
    \param adapt The mode.
*/
SPAN_DECLARE(void) modem_echo_can_adaption_mode(modem_echo_can_state_t *ec, int adapt);

/*! Process a sample through a modem echo canceller.
    \param ec The echo canceller context.
    \param tx The transmitted audio sample.
    \param rx The received audio sample.
    eturn The clean (echo cancelled) received sample.
*/
SPAN_DECLARE(int16_t) modem_echo_can_update(modem_echo_can_state_t *ec, int16_t tx, int16_t rx);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
