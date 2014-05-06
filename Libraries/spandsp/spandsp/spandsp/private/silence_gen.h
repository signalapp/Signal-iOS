/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/silence_gen.c - A silence generator, for inserting timed silences.
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
 * $Id: silence_gen.h,v 1.1 2009/04/12 03:29:58 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_SILENCE_GEN_H_)
#define _SPANDSP_PRIVATE_SILENCE_GEN_H_

struct silence_gen_state_s
{
    /*! \brief The callback function used to report status changes. */
    modem_tx_status_func_t status_handler;
    /*! \brief A user specified opaque pointer passed to the status function. */
    void *status_user_data;

    int remaining_samples;
    int total_samples;
};

#endif
/*- End of file ------------------------------------------------------------*/
