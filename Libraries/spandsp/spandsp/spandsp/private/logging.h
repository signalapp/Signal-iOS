/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/logging.h - definitions for error and debug logging.
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
 * $Id: logging.h,v 1.1 2008/11/30 13:44:35 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_LOGGING_H_)
#define _SPANDSP_PRIVATE_LOGGING_H_

/*!
    Logging descriptor. This defines the working state for a single instance of
    the logging facility for spandsp.
*/
struct logging_state_s
{
    int level;
    int samples_per_second;
    int64_t elapsed_samples;
    const char *tag;
    const char *protocol;

    message_handler_func_t span_message;
    error_handler_func_t span_error;
};

#endif
/*- End of file ------------------------------------------------------------*/
