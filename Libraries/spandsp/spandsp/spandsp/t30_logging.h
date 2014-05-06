/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t30_logging.h - definitions for T.30 fax processing
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
 * $Id: t30_logging.h,v 1.4 2009/02/03 16:28:41 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T30_LOGGING_H_)
#define _SPANDSP_T30_LOGGING_H_

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Return a text name for a T.30 frame type.
    \brief Return a text name for a T.30 frame type.
    \param x The frametype octet.
    \return A pointer to the text name for the frame type. If the frame type is
            not value, the string "???" is returned. */
SPAN_DECLARE(const char *) t30_frametype(uint8_t x);

/*! Decode a DIS, DTC or DCS frame, and log the contents.
    \brief Decode a DIS, DTC or DCS frame, and log the contents.
    \param s The T.30 context.
    \param dis A pointer to the frame to be decoded.
    \param len The length of the frame. */
SPAN_DECLARE(void) t30_decode_dis_dtc_dcs(t30_state_t *s, const uint8_t *dis, int len);

/*! Convert a phase E completion code to a short text description.
    \brief Convert a phase E completion code to a short text description.
    \param result The result code.
    \return A pointer to the description. */
SPAN_DECLARE(const char *) t30_completion_code_to_str(int result);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
