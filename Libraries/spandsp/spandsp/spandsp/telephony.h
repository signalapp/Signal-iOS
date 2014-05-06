/*
 * SpanDSP - a series of DSP components for telephony
 *
 * telephony.h - some very basic telephony definitions
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2003 Steve Underwood
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
 * $Id: telephony.h,v 1.18.4.2 2009/12/21 18:38:06 steveu Exp $
 */

#if !defined(_SPANDSP_TELEPHONY_H_)
#define _SPANDSP_TELEPHONY_H_

#if defined(_M_IX86)  ||  defined(_M_X64)
#if defined(LIBSPANDSP_EXPORTS)
#define SPAN_DECLARE(type)              __declspec(dllexport) type __stdcall
#define SPAN_DECLARE_NONSTD(type)       __declspec(dllexport) type __cdecl
#define SPAN_DECLARE_DATA               __declspec(dllexport)
#else
#define SPAN_DECLARE(type)              __declspec(dllimport) type __stdcall
#define SPAN_DECLARE_NONSTD(type)       __declspec(dllimport) type __cdecl
#define SPAN_DECLARE_DATA               __declspec(dllimport)
#endif
#elif defined(SPANDSP_USE_EXPORT_CAPABILITY)  &&  (defined(__GNUC__)  ||  defined(__SUNCC__))
#define SPAN_DECLARE(type)              __attribute__((visibility("default"))) type
#define SPAN_DECLARE_NONSTD(type)       __attribute__((visibility("default"))) type
#define SPAN_DECLARE_DATA               __attribute__((visibility("default")))
#else
#define SPAN_DECLARE(type)              /**/ type
#define SPAN_DECLARE_NONSTD(type)       /**/ type
#define SPAN_DECLARE_DATA               /**/
#endif

#define SAMPLE_RATE                 8000

/* This is based on A-law, but u-law is only 0.03dB different */
#define DBM0_MAX_POWER              (3.14f + 3.02f)
#define DBM0_MAX_SINE_POWER         (3.14f)
/* This is based on the ITU definition of dbOv in G.100.1 */
#define DBOV_MAX_POWER              (0.0f)
#define DBOV_MAX_SINE_POWER         (-3.02f)

/*! \brief A handler for pure receive. The buffer cannot be altered. */
typedef int (span_rx_handler_t)(void *s, const int16_t amp[], int len);

/*! \brief A handler for receive, where the buffer can be altered. */
typedef int (span_mod_handler_t)(void *s, int16_t amp[], int len);

/*! \brief A handler for missing receive data fill-in. */
typedef int (span_rx_fillin_handler_t)(void *s, int len);

/*! \brief A handler for transmit, where the buffer will be filled. */
typedef int (span_tx_handler_t)(void *s, int16_t amp[], int max_len);

#define ms_to_samples(t)            ((t)*(SAMPLE_RATE/1000))
#define us_to_samples(t)            ((t)/(1000000/SAMPLE_RATE))

#if !defined(FALSE)
#define FALSE 0
#endif
#if !defined(TRUE)
#define TRUE (!FALSE)
#endif

#if defined(__cplusplus)
/* C++ doesn't seem to have sane rounding functions/macros yet */
#if !defined(WIN32)
#define lrint(x) ((long int) (x))
#define lrintf(x) ((long int) (x))
#endif
#endif

#endif
/*- End of file ------------------------------------------------------------*/
