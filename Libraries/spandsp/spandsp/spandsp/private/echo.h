/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/echo.h - An echo cancellor, suitable for electrical and acoustic
 *	                cancellation. This code does not currently comply with
 *	                any relevant standards (e.g. G.164/5/7/8).
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
 * $Id: echo.h,v 1.1 2009/09/22 13:11:04 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_ECHO_H_)
#define _SPANDSP_PRIVATE_ECHO_H_

/*!
    G.168 echo canceller descriptor. This defines the working state for a line
    echo canceller.
*/
struct echo_can_state_s
{
    int tx_power[4];
    int rx_power[3];
    int clean_rx_power;

    int rx_power_threshold;
    int nonupdate_dwell;

    int curr_pos;
	
    int taps;
    int tap_mask;
    int adaption_mode;
    
    int32_t supp_test1;
    int32_t supp_test2;
    int32_t supp1;
    int32_t supp2;
    int vad;
    int cng;

    int16_t geigel_max;
    int geigel_lag;
    int dtd_onset;
    int tap_set;
    int tap_rotate_counter;

    int32_t latest_correction;  /* Indication of the magnitude of the latest
                                   adaption, or a code to indicate why adaption
                                   was skipped, for test purposes */
    int32_t last_acf[28];
    int narrowband_count;
    int narrowband_score;

    fir16_state_t fir_state;
    /*! Echo FIR taps (16 bit version) */
    int16_t *fir_taps16[4];
    /*! Echo FIR taps (32 bit version) */
    int32_t *fir_taps32;

    /* DC and near DC blocking filter states */
    int32_t tx_hpf[2];
    int32_t rx_hpf[2];
   
    /* Parameters for the optional Hoth noise generator */
    int cng_level;
    int cng_rndnum;
    int cng_filter;
    
    /* Snapshot sample of coeffs used for development */
    int16_t *snapshot;       
};

#endif
/*- End of file ------------------------------------------------------------*/
