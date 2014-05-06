/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t35.h - ITU T.35 FAX non-standard facility processing.
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
 * $Id: t35.h,v 1.15 2009/01/31 08:48:11 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T35_H_)
#define _SPANDSP_T35_H_

/*! \page t35_page T.35 manufacturer specific processing for FAX machines
\section t35_page_sec_1 What does it do?
???.

\section t35_page_sec_2 How does it work?
???.
*/

/*! A table of the country names associated with each possible value of the T.35 country code
    selector octet. */
extern const char *t35_country_codes[256];

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Decode an NSF field to try to determine the make and model of the
    remote machine.
    \brief Decode an NSF field.
    \param msg The NSF message.
    \param len The length of the NSF message.
    \param country A pointer which will be pointed to the identified country of origin.
           If a NULL pointer is given, the country of origin will not be returned.
           If the country of origin is not identified, NULL will be returned.
    \param vendor A pointer which will be pointed to the identified vendor.
           If a NULL pointer is given, the vendor ID will not be returned.
           If the vendor is not identified, NULL will be returned.
    \param model A pointer which will be pointed to the identified model.
           If a NULL pointer is given, the model will not be returned.
           If the model is not identified, NULL will be returned.
    \return TRUE if the machine was identified, otherwise FALSE.
*/
SPAN_DECLARE(int) t35_decode(const uint8_t *msg, int len, const char **country, const char **vendor, const char **model);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
