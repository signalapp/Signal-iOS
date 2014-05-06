/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/gsm0610.h - GSM 06.10 full rate speech codec.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2006 Steve Underwood
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
 * $Id: gsm0610.h,v 1.2 2008/11/15 14:27:29 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_GSM0610_H_)
#define _SPANDSP_PRIVATE_GSM0610_H_

/*!
    GSM 06.10 FR codec state descriptor. This defines the state of
    a single working instance of the GSM 06.10 FR encoder or decoder.
*/
struct gsm0610_state_s
{
    /*! \brief One of the packing modes */
    int packing;

    int16_t dp0[280];

    /*! Preprocessing */
    int16_t z1;
    int32_t L_z2;
    /*! Pre-emphasis */
    int16_t mp;

    /*! Short term delay filter */
    int16_t u[8];
    int16_t LARpp[2][8];
    int16_t j;

    /*! Long term synthesis */
    int16_t nrp;
    /*! Short term synthesis */
    int16_t v[9];
    /*! Decoder postprocessing */
    int16_t msr;
    
    /*! Encoder data */
    int16_t e[50];
};

#endif
/*- End of include ---------------------------------------------------------*/
