/*
 * SpanDSP - a series of DSP components for telephony
 *
 * bell_r2_mf.h - Bell MF and MFC/R2 tone generation and detection.
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
 * $Id: bell_r2_mf.h,v 1.2 2008/10/13 14:19:18 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_BELL_R2_MF_H_)
#define _SPANDSP_PRIVATE_BELL_R2_MF_H_

/*!
    Bell MF generator state descriptor. This defines the state of a single
    working instance of a Bell MF generator.
*/
struct bell_mf_tx_state_s
{
    /*! The tone generator. */
    tone_gen_state_t tones;
    int current_sample;
    union
    {
        queue_state_t queue;
        uint8_t buf[QUEUE_STATE_T_SIZE(MAX_BELL_MF_DIGITS)];
    } queue;
};

/*!
    Bell MF digit detector descriptor.
*/
struct bell_mf_rx_state_s
{
    /*! Optional callback funcion to deliver received digits. */
    digits_rx_callback_t digits_callback;
    /*! An opaque pointer passed to the callback function. */
    void *digits_callback_data;
    /*! Tone detector working states */
    goertzel_state_t out[6];
    /*! Short term history of results from the tone detection, using in persistence checking */
    uint8_t hits[5];
    /*! The current sample number within a processing block. */
    int current_sample;

    /*! The number of digits which have been lost due to buffer overflows. */
    int lost_digits;
    /*! The number of digits currently in the digit buffer. */
    int current_digits;
    /*! The received digits buffer. This is a NULL terminated string. */
    char digits[MAX_BELL_MF_DIGITS + 1];
};

/*!
    MFC/R2 tone detector descriptor.
*/
struct r2_mf_tx_state_s
{
    /*! The tone generator. */
    tone_gen_state_t tone;
    /*! TRUE if generating forward tones, otherwise generating reverse tones. */
    int fwd;
    /*! The current digit being generated. */
    int digit;
};

/*!
    MFC/R2 tone detector descriptor.
*/
struct r2_mf_rx_state_s
{
    /*! Optional callback funcion to deliver received digits. */
    tone_report_func_t callback;
    /*! An opaque pointer passed to the callback function. */
    void *callback_data;
    /*! TRUE is we are detecting forward tones. FALSE if we are detecting backward tones */
    int fwd;
    /*! Tone detector working states */
    goertzel_state_t out[6];
    /*! The current sample number within a processing block. */
    int current_sample;
    /*! The currently detected digit. */
    int current_digit;
};

#endif
/*- End of file ------------------------------------------------------------*/
