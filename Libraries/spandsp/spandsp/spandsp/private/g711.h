/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/g711.h - In line A-law and u-law conversion routines
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001 Steve Underwood
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
 * $Id: g711.h,v 1.2 2009/04/12 09:12:11 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_G711_H_)
#define _SPANDSP_PRIVATE_G711_H_

/*!
    G.711 state
 */
struct g711_state_s
{
    /*! One of the G.711_xxx options */
    int mode;
};

#endif
/*- End of file ------------------------------------------------------------*/
