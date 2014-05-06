/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/lpc10.h - LPC10 low bit rate speech codec.
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
 * $Id: lpc10.h,v 1.3 2009/04/12 09:12:11 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_LPC10_H_)
#define _SPANDSP_PRIVATE_LPC10_H_

/*!
    LPC10 codec encoder state descriptor. This defines the state of
    a single working instance of the LPC10 encoder.
*/
struct lpc10_encode_state_s
{
    /*! \brief ??? */
    int error_correction;

    /* State used only by function high_pass_100hz */
    /*! \brief ??? */
    float z11;
    /*! \brief ??? */
    float z21;
    /*! \brief ??? */
    float z12;
    /*! \brief ??? */
    float z22;
    
    /* State used by function lpc10_analyse */
    /*! \brief ??? */
    float inbuf[LPC10_SAMPLES_PER_FRAME*3];
    /*! \brief ??? */
    float pebuf[LPC10_SAMPLES_PER_FRAME*3];
    /*! \brief ??? */
    float lpbuf[696];
    /*! \brief ??? */
    float ivbuf[312];
    /*! \brief ??? */
    float bias;
    /*! \brief No initial value necessary */
    int32_t osbuf[10];
    /*! \brief Initial value 1 */
    int32_t osptr;
    /*! \brief ??? */
    int32_t obound[3];
    /*! \brief Initial value vwin[2][0] = 307; vwin[2][1] = 462; */
    int32_t vwin[3][2];
    /*! \brief Initial value awin[2][0] = 307; awin[2][1] = 462; */
    int32_t awin[3][2];
    /*! \brief ??? */
    int32_t voibuf[4][2];
    /*! \brief ??? */
    float rmsbuf[3];
    /*! \brief ??? */
    float rcbuf[3][10];
    /*! \brief ??? */
    float zpre;

    /* State used by function onset */
    /*! \brief ??? */
    float n;
    /*! \brief Initial value 1.0f */
    float d__;
    /*! \brief No initial value necessary */
    float fpc;
    /*! \brief ??? */
    float l2buf[16];
    /*! \brief ??? */
    float l2sum1;
    /*! \brief Initial value 1 */
    int32_t l2ptr1;
    /*! \brief Initial value 9 */
    int32_t l2ptr2;
    /*! \brief No initial value necessary */
    int32_t lasti;
    /*! \brief Initial value FALSE */
    int hyst;

    /* State used by function lpc10_voicing */
    /*! \brief Initial value 20.0f */
    float dither;
    /*! \brief ??? */
    float snr;
    /*! \brief ??? */
    float maxmin;
    /*! \brief Initial value is probably unnecessary */
    float voice[3][2];
    /*! \brief ??? */
    int32_t lbve;
    /*! \brief ??? */
    int32_t lbue;
    /*! \brief ??? */
    int32_t fbve;
    /*! \brief ??? */
    int32_t fbue;
    /*! \brief ??? */
    int32_t ofbue;
    /*! \brief ??? */
    int32_t sfbue;
    /*! \brief ??? */
    int32_t olbue;
    /*! \brief ??? */
    int32_t slbue;

    /* State used by function dynamic_pitch_tracking */
    /*! \brief ??? */
    float s[60];
    /*! \brief ??? */
    int32_t p[2][60];
    /*! \brief ??? */
    int32_t ipoint;
    /*! \brief ??? */
    float alphax;

    /* State used by function lpc10_pack */
    /*! \brief ??? */
    int32_t isync;
};

/*!
    LPC10 codec decoder state descriptor. This defines the state of
    a single working instance of the LPC10 decoder.
*/
struct lpc10_decode_state_s
{
    /*! \brief ??? */
    int error_correction;

    /* State used by function decode */
    /*! \brief Initial value 60 */
    int32_t iptold;
    /*! \brief Initial value TRUE */
    int first;
    /*! \brief ??? */
    int32_t ivp2h;
    /*! \brief ??? */
    int32_t iovoic;
    /*! \brief Initial value 60. */
    int32_t iavgp;
    /*! \brief ??? */
    int32_t erate;
    /*! \brief ??? */
    int32_t drc[10][3];
    /*! \brief ??? */
    int32_t dpit[3];
    /*! \brief ??? */
    int32_t drms[3];

    /* State used by function synths */
    /*! \brief ??? */
    float buf[LPC10_SAMPLES_PER_FRAME*2];
    /*! \brief Initial value LPC10_SAMPLES_PER_FRAME */
    int32_t buflen;

    /* State used by function pitsyn */
    /*! \brief No initial value necessary as long as first_pitsyn is initially TRUE */
    int32_t ivoico;
    /*! \brief  No initial value necessary as long as first_pitsyn is initially TRUE */
    int32_t ipito;
    /*! \brief Initial value 1.0f */
    float rmso;
    /*! \brief No initial value necessary as long as first_pitsyn is initially TRUE */
    float rco[10];
    /*! \brief No initial value necessary as long as first_pitsyn is initially TRUE */
    int32_t jsamp;
    /*! \brief Initial value TRUE */
    int first_pitsyn;

    /* State used by function bsynz */
    /*! \brief ??? */
    int32_t ipo;
    /*! \brief ??? */
    float exc[166];
    /*! \brief ??? */
    float exc2[166];
    /*! \brief ??? */
    float lpi[3];
    /*! \brief ??? */
    float hpi[3];
    /*! \brief ??? */
    float rmso_bsynz;

    /* State used by function random */
    /*! \brief ??? */
    int32_t j;
    /*! \brief ??? */
    int32_t k;
    /*! \brief ??? */
    int16_t y[5];

    /* State used by function deemp */
    /*! \brief ??? */
    float dei[2];
    /*! \brief ??? */
    float deo[3];
};

#endif
/*- End of include ---------------------------------------------------------*/
