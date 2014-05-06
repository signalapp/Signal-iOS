/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/schedule.h
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004 Steve Underwood
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
 * $Id: schedule.h,v 1.1 2008/11/30 05:43:37 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_SCHEDULE_H_)
#define _SPANDSP_PRIVATE_SCHEDULE_H_

/*! A scheduled event entry. */
struct span_sched_s
{
    uint64_t when;
    span_sched_callback_func_t callback;
    void *user_data;
};

/*! A scheduled event queue. */
struct span_sched_state_s
{
    uint64_t ticker;
    int allocated;
    int max_to_date;
    span_sched_t *sched;
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
