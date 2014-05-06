/*
 * SpanDSP - a series of DSP components for telephony
 *
 * echo.h - An echo cancellor, suitable for electrical and acoustic
 *	        cancellation. This code does not currently comply with
 *	        any relevant standards (e.g. G.164/5/7/8).
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
 * $Id: echo.h,v 1.20 2009/09/22 13:11:04 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_ECHO_H_)
#define _SPANDSP_ECHO_H_

/*! \page echo_can_page Line echo cancellation for voice

\section echo_can_page_sec_1 What does it do?
This module aims to provide G.168-2002 compliant echo cancellation, to remove
electrical echoes (e.g. from 2-4 wire hybrids) from voice calls.

\section echo_can_page_sec_2 How does it work?
The heart of the echo cancellor is FIR filter. This is adapted to match the echo
impulse response of the telephone line. It must be long enough to adequately cover
the duration of that impulse response. The signal transmitted to the telephone line
is passed through the FIR filter. Once the FIR is properly adapted, the resulting
output is an estimate of the echo signal received from the line. This is subtracted
from the received signal. The result is an estimate of the signal which originated
at the far end of the line, free from echos of our own transmitted signal. 

The least mean squares (LMS) algorithm is attributed to Widrow and Hoff, and was
introduced in 1960. It is the commonest form of filter adaption used in things
like modem line equalisers and line echo cancellers. There it works very well.
However, it only works well for signals of constant amplitude. It works very poorly
for things like speech echo cancellation, where the signal level varies widely.
This is quite easy to fix. If the signal level is normalised - similar to applying
AGC - LMS can work as well for a signal of varying amplitude as it does for a modem
signal. This normalised least mean squares (NLMS) algorithm is the commonest one used
for speech echo cancellation. Many other algorithms exist - e.g. RLS (essentially
the same as Kalman filtering), FAP, etc. Some perform significantly better than NLMS.
However, factors such as computational complexity and patents favour the use of NLMS.

A simple refinement to NLMS can improve its performance with speech. NLMS tends
to adapt best to the strongest parts of a signal. If the signal is white noise,
the NLMS algorithm works very well. However, speech has more low frequency than
high frequency content. Pre-whitening (i.e. filtering the signal to flatten
its spectrum) the echo signal improves the adapt rate for speech, and ensures the
final residual signal is not heavily biased towards high frequencies. A very low
complexity filter is adequate for this, so pre-whitening adds little to the
compute requirements of the echo canceller.

An FIR filter adapted using pre-whitened NLMS performs well, provided certain
conditions are met: 

    - The transmitted signal has poor self-correlation.
    - There is no signal being generated within the environment being cancelled.

The difficulty is that neither of these can be guaranteed.

If the adaption is performed while transmitting noise (or something fairly noise
like, such as voice) the adaption works very well. If the adaption is performed
while transmitting something highly correlative (typically narrow band energy
such as signalling tones or DTMF), the adaption can go seriously wrong. The reason
is there is only one solution for the adaption on a near random signal - the impulse
response of the line. For a repetitive signal, there are any number of solutions
which converge the adaption, and nothing guides the adaption to choose the generalised
one. Allowing an untrained canceller to converge on this kind of narrowband
energy probably a good thing, since at least it cancels the tones. Allowing a well
converged canceller to continue converging on such energy is just a way to ruin
its generalised adaption. A narrowband detector is needed, so adapation can be
suspended at appropriate times.

The adaption process is based on trying to eliminate the received signal. When
there is any signal from within the environment being cancelled it may upset the
adaption process. Similarly, if the signal we are transmitting is small, noise
may dominate and disturb the adaption process. If we can ensure that the
adaption is only performed when we are transmitting a significant signal level,
and the environment is not, things will be OK. Clearly, it is easy to tell when
we are sending a significant signal. Telling, if the environment is generating a
significant signal, and doing it with sufficient speed that the adaption will
not have diverged too much more we stop it, is a little harder. 

The key problem in detecting when the environment is sourcing significant energy
is that we must do this very quickly. Given a reasonably long sample of the
received signal, there are a number of strategies which may be used to assess
whether that signal contains a strong far end component. However, by the time
that assessment is complete the far end signal will have already caused major
mis-convergence in the adaption process. An assessment algorithm is needed which
produces a fairly accurate result from a very short burst of far end energy. 

\section echo_can_page_sec_3 How do I use it?
The echo cancellor processes both the transmit and receive streams sample by
sample. The processing function is not declared inline. Unfortunately,
cancellation requires many operations per sample, so the call overhead is only a
minor burden. 
*/

#include "fir.h"

/* Mask bits for the adaption mode */
enum
{
    ECHO_CAN_USE_ADAPTION = 0x01,
    ECHO_CAN_USE_NLP = 0x02,
    ECHO_CAN_USE_CNG = 0x04,
    ECHO_CAN_USE_CLIP = 0x08,
    ECHO_CAN_USE_SUPPRESSOR = 0x10,
    ECHO_CAN_USE_TX_HPF = 0x20,
    ECHO_CAN_USE_RX_HPF = 0x40,
    ECHO_CAN_DISABLE = 0x80
};

/*!
    G.168 echo canceller descriptor. This defines the working state for a line
    echo canceller.
*/
typedef struct echo_can_state_s echo_can_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Create a voice echo canceller context.
    \param len The length of the canceller, in samples.
    \return The new canceller context, or NULL if the canceller could not be created.
*/
SPAN_DECLARE(echo_can_state_t *) echo_can_init(int len, int adaption_mode);

/*! Release a voice echo canceller context.
    \param ec The echo canceller context.
    \return 0 for OK, else -1.
*/
SPAN_DECLARE(int) echo_can_release(echo_can_state_t *ec);

/*! Free a voice echo canceller context.
    \param ec The echo canceller context.
    \return 0 for OK, else -1.
*/
SPAN_DECLARE(int) echo_can_free(echo_can_state_t *ec);

/*! Flush (reinitialise) a voice echo canceller context.
    \param ec The echo canceller context.
*/
SPAN_DECLARE(void) echo_can_flush(echo_can_state_t *ec);

/*! Set the adaption mode of a voice echo canceller context.
    \param ec The echo canceller context.
    \param adaption_mode The mode.
*/
SPAN_DECLARE(void) echo_can_adaption_mode(echo_can_state_t *ec, int adaption_mode);

/*! Process a sample through a voice echo canceller.
    \param ec The echo canceller context.
    \param tx The transmitted audio sample.
    \param rx The received audio sample.
    \return The clean (echo cancelled) received sample.
*/
SPAN_DECLARE(int16_t) echo_can_update(echo_can_state_t *ec, int16_t tx, int16_t rx);

/*! Process to high pass filter the tx signal.
    \param ec The echo canceller context.
    \param tx The transmitted auio sample.
    \return The HP filtered transmit sample, send this to your D/A.
*/
SPAN_DECLARE(int16_t) echo_can_hpf_tx(echo_can_state_t *ec, int16_t tx);

SPAN_DECLARE(void) echo_can_snapshot(echo_can_state_t *ec);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
