/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/awgn.h - An additive Gaussian white noise generator
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
 * $Id: awgn.h,v 1.1 2008/11/30 12:38:27 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_AWGN_H_)
#define _SPANDSP_PRIVATE_AWGN_H_

/*!
    AWGN generator descriptor. This contains all the state information for an AWGN generator.
 */
struct awgn_state_s
{
    double rms;
    long int ix1;
    long int ix2;
    long int ix3;
    double r[98];
    double gset;
    int iset;
};

#endif
/*- End of file ------------------------------------------------------------*/
