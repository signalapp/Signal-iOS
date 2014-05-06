/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/queue.h - simple in process message queuing
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
 * $Id: queue.h,v 1.2 2009/01/31 08:48:11 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_QUEUE_H_)
#define _SPANDSP_PRIVATE_QUEUE_H_

/*!
    Queue descriptor. This defines the working state for a single instance of
    a byte stream or message oriented queue.
*/
struct queue_state_s
{
    /*! \brief Flags indicating the mode of the queue. */
    int flags;
    /*! \brief The length of the data buffer. */
    int len;
    /*! \brief The buffer input pointer. */
    volatile int iptr;
    /*! \brief The buffer output pointer. */
    volatile int optr;
#if defined(SPANDSP_FULLY_DEFINE_QUEUE_STATE_T)
    /*! \brief The data buffer, sized at the time the structure is created. */
    uint8_t data[];
#endif
};

#endif
/*- End of file ------------------------------------------------------------*/
