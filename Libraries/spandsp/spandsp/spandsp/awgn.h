/*
 * SpanDSP - a series of DSP components for telephony
 *
 * awgn.h - An additive Gaussian white noise generator
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
 * $Id: awgn.h,v 1.18 2009/02/10 13:06:47 steveu Exp $
 */

/*! \file */

/* This code is based on some demonstration code in a research
   paper somewhere. I can't track down where I got the original from,
   so that due recognition can be given. The original had no explicit
   copyright notice, and I hope nobody objects to its use here.
   
   Having a reasonable Gaussian noise generator is pretty important for
   telephony testing (in fact, pretty much any DSP testing), and this
   one seems to have served me OK. Since the generation of Gaussian
   noise is only for test purposes, and not a core system component,
   I don't intend to worry excessively about copyright issues, unless
   someone worries me.
        
   The non-core nature of this code also explains why it is unlikely
   to ever be optimised. */

#if !defined(_SPANDSP_AWGN_H_)
#define _SPANDSP_AWGN_H_

/*! \page awgn_page Additive white gaussian noise (AWGN) generation

\section awgn_page_sec_1 What does it do?
Adding noise is not the most useful thing in most DSP applications, but it is
awfully useful for test suites. 

\section awgn_page_sec_2 How does it work?

This code is based on some demonstration code in a research paper somewhere. I
can't track down where I got the original from, so that due recognition can be
given. The original had no explicit copyright notice, and I hope nobody objects
to its use here. 

Having a reasonable Gaussian noise generator is pretty important for telephony
testing (in fact, pretty much any DSP testing), and this one seems to have
served me OK. Since the generation of Gaussian noise is only for test purposes,
and not a core system component, I don't intend to worry excessively about
copyright issues, unless someone worries me. 

The non-core nature of this code also explains why it is unlikely to ever be
optimised.
*/

/*!
    AWGN generator descriptor. This contains all the state information for an AWGN generator.
 */
typedef struct awgn_state_s awgn_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(awgn_state_t *) awgn_init_dbm0(awgn_state_t *s, int idum, float level);

SPAN_DECLARE(awgn_state_t *) awgn_init_dbov(awgn_state_t *s, int idum, float level);

SPAN_DECLARE(int) awgn_release(awgn_state_t *s);

SPAN_DECLARE(int) awgn_free(awgn_state_t *s);

SPAN_DECLARE(int16_t) awgn(awgn_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
