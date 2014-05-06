/*
 * SpanDSP - a series of DSP components for telephony
 *
 * crc.h
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
 * $Id: crc.h,v 1.5 2009/01/31 08:48:11 steveu Exp $
 */

/*! \file */

/*! \page crc_page CRC

\section crc_page_sec_1 What does it do?

\section crc_page_sec_2 How does it work?
*/

#if !defined(_SPANDSP_CRC_H_)
#define _SPANDSP_CRC_H_

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Calculate the ITU/CCITT CRC-32 value in buffer.
    \param buf The buffer containing the data.
    \param len The length of the frame.
    \param crc The initial CRC value. This is usually 0xFFFFFFFF, or 0 for a new block (it depends on
           the application). It is previous returned CRC value for the continuation of a block.
    \return The CRC value.
*/
SPAN_DECLARE(uint32_t) crc_itu32_calc(const uint8_t *buf, int len, uint32_t crc);

/*! \brief Append an ITU/CCITT CRC-32 value to a frame.
    \param buf The buffer containing the frame. This must be at least 2 bytes longer than
               the frame it contains, to allow room for the CRC value.
    \param len The length of the frame.
    \return The new length of the frame.
*/
SPAN_DECLARE(int) crc_itu32_append(uint8_t *buf, int len);

/*! \brief Check the ITU/CCITT CRC-32 value in a frame.
    \param buf The buffer containing the frame.
    \param len The length of the frame.
    \return TRUE if the CRC is OK, else FALSE.
*/
SPAN_DECLARE(int) crc_itu32_check(const uint8_t *buf, int len);

/*! \brief Calculate the ITU/CCITT CRC-16 value in buffer.
    \param buf The buffer containing the data.
    \param len The length of the frame.
    \param crc The initial CRC value. This is usually 0xFFFF, or 0 for a new block (it depends on
           the application). It is previous returned CRC value for the continuation of a block.
    \return The CRC value.
*/
SPAN_DECLARE(uint16_t) crc_itu16_calc(const uint8_t *buf, int len, uint16_t crc);

/*! \brief Append an ITU/CCITT CRC-16 value to a frame.
    \param buf The buffer containing the frame. This must be at least 2 bytes longer than
               the frame it contains, to allow room for the CRC value.
    \param len The length of the frame.
    \return The new length of the frame.
*/
SPAN_DECLARE(int) crc_itu16_append(uint8_t *buf, int len);

/*! \brief Check the ITU/CCITT CRC-16 value in a frame.
    \param buf The buffer containing the frame.
    \param len The length of the frame.
    \return TRUE if the CRC is OK, else FALSE.
*/
SPAN_DECLARE(int) crc_itu16_check(const uint8_t *buf, int len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
