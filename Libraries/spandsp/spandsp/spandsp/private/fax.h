/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/fax.h - private definitions for analogue line ITU T.30 fax processing
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
 * $Id: fax.h,v 1.1 2008/10/13 13:14:01 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_FAX_H_)
#define _SPANDSP_PRIVATE_FAX_H_

/*!
    Analogue line T.30 FAX channel descriptor. This defines the state of a single working
    instance of an analogue line soft-FAX machine.
*/
struct fax_state_s
{
    /*! \brief The T.30 back-end */
    t30_state_t t30;
    
    /*! \brief The analogue modem front-end */
    fax_modems_state_t modems;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
