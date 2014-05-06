/*
 * SpanDSP - a series of DSP components for telephony
 *
 * logging.h - definitions for error and debug logging.
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
 * $Id: logging.h,v 1.20 2009/02/10 17:44:18 steveu Exp $
 */

/*! \file */

/*! \page logging_page Logging
\section logging_page_sec_1 What does it do?
???.
*/

#if !defined(_SPANDSP_LOGGING_H_)
#define _SPANDSP_LOGGING_H_

/*! General logging function for spandsp logging. */
typedef void (*message_handler_func_t)(int level, const char *text);

/*! Error logging function for spandsp logging. */
typedef void (*error_handler_func_t)(const char *text);

/* Logging elements */
enum
{
    SPAN_LOG_SEVERITY_MASK              = 0x00FF,
    SPAN_LOG_SHOW_DATE                  = 0x0100,
    SPAN_LOG_SHOW_SAMPLE_TIME           = 0x0200,
    SPAN_LOG_SHOW_SEVERITY              = 0x0400,
    SPAN_LOG_SHOW_PROTOCOL              = 0x0800,
    SPAN_LOG_SHOW_VARIANT               = 0x1000,
    SPAN_LOG_SHOW_TAG                   = 0x2000,
    SPAN_LOG_SUPPRESS_LABELLING         = 0x8000
};

/* Logging severity levels */
enum
{
    SPAN_LOG_NONE                       = 0,
    SPAN_LOG_ERROR                      = 1,
    SPAN_LOG_WARNING                    = 2,
    SPAN_LOG_PROTOCOL_ERROR             = 3,
    SPAN_LOG_PROTOCOL_WARNING           = 4,
    SPAN_LOG_FLOW                       = 5,
    SPAN_LOG_FLOW_2                     = 6,
    SPAN_LOG_FLOW_3                     = 7,
    SPAN_LOG_DEBUG                      = 8,
    SPAN_LOG_DEBUG_2                    = 9,
    SPAN_LOG_DEBUG_3                    = 10
};

/*!
    Logging descriptor. This defines the working state for a single instance of
    the logging facility for spandsp.
*/
typedef struct logging_state_s logging_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Test if logging of a specified severity level is enabled.
    \brief Test if logging of a specified severity level is enabled.
    \param s The logging context.
    \param level The severity level to be tested.
    \return TRUE if logging is enable, else FALSE.
*/
SPAN_DECLARE(int) span_log_test(logging_state_t *s, int level);

/*! Generate a log entry.
    \brief Generate a log entry.
    \param s The logging context.
    \param level The severity level of the entry.
    \param format ???
    \return 0 if no output generated, else 1.
*/
SPAN_DECLARE(int) span_log(logging_state_t *s, int level, const char *format, ...);

/*! Generate a log entry displaying the contents of a buffer.
    \brief Generate a log entry displaying the contents of a buffer
    \param s The logging context.
    \param level The severity level of the entry.
    \param tag A label for the log entry.
    \param buf The buffer to be dumped to the log.
    \param len The length of buf.
    \return 0 if no output generated, else 1.
*/
SPAN_DECLARE(int) span_log_buf(logging_state_t *s, int level, const char *tag, const uint8_t *buf, int len);

SPAN_DECLARE(int) span_log_set_level(logging_state_t *s, int level);

SPAN_DECLARE(int) span_log_set_tag(logging_state_t *s, const char *tag);

SPAN_DECLARE(int) span_log_set_protocol(logging_state_t *s, const char *protocol);

SPAN_DECLARE(int) span_log_set_sample_rate(logging_state_t *s, int samples_per_second);

SPAN_DECLARE(int) span_log_bump_samples(logging_state_t *s, int samples);

SPAN_DECLARE(void) span_log_set_message_handler(logging_state_t *s, message_handler_func_t func);

SPAN_DECLARE(void) span_log_set_error_handler(logging_state_t *s, error_handler_func_t func);

SPAN_DECLARE(void) span_set_message_handler(message_handler_func_t func);

SPAN_DECLARE(void) span_set_error_handler(error_handler_func_t func);

SPAN_DECLARE(logging_state_t *) span_log_init(logging_state_t *s, int level, const char *tag);

SPAN_DECLARE(int) span_log_release(logging_state_t *s);

SPAN_DECLARE(int) span_log_free(logging_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
