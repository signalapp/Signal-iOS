/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/modem_echo.h - An echo cancellor, suitable for electrical echos in GSTN modems
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
 * $Id: modem_echo.h,v 1.1 2009/09/22 13:11:04 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_MODEM_ECHO_H_)
#define _SPANDSP_PRIVATE_MODEM_ECHO_H_

/*!
    Modem line echo canceller descriptor. This defines the working state for a line
    echo canceller.
*/
struct modem_echo_can_state_s
{
    int adapt;
    int taps;

    fir16_state_t fir_state;
    /*! Echo FIR taps (16 bit version) */
    int16_t *fir_taps16;
    /*! Echo FIR taps (32 bit version) */
    int32_t *fir_taps32;

    int tx_power;
    int rx_power;

    int curr_pos;
};

#endif
/*- End of file ------------------------------------------------------------*/
