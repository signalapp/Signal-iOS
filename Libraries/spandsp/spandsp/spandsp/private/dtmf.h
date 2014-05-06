/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/dtmf.h - DTMF tone generation and detection 
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001, 2005 Steve Underwood
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
 * $Id: dtmf.h,v 1.1 2008/10/13 13:14:01 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_DTMF_H_)
#define _SPANDSP_PRIVATE_DTMF_H_

/*!
    DTMF generator state descriptor. This defines the state of a single
    working instance of a DTMF generator.
*/
struct dtmf_tx_state_s
{
    tone_gen_state_t tones;
    float low_level;
    float high_level;
    int on_time;
    int off_time;
    union
    {
        queue_state_t queue;
        uint8_t buf[QUEUE_STATE_T_SIZE(MAX_DTMF_DIGITS)];
    } queue;
};

/*!
    DTMF digit detector descriptor.
*/
struct dtmf_rx_state_s
{
    /*! Optional callback funcion to deliver received digits. */
    digits_rx_callback_t digits_callback;
    /*! An opaque pointer passed to the callback function. */
    void *digits_callback_data;
    /*! Optional callback funcion to deliver real time digit state changes. */
    tone_report_func_t realtime_callback;
    /*! An opaque pointer passed to the real time callback function. */
    void *realtime_callback_data;
    /*! TRUE if dialtone should be filtered before processing */
    int filter_dialtone;
#if defined(SPANDSP_USE_FIXED_POINT)
    /*! 350Hz filter state for the optional dialtone filter. */
    float z350[2];
    /*! 440Hz filter state for the optional dialtone filter. */
    float z440[2];
    /*! Maximum acceptable "normal" (lower bigger than higher) twist ratio. */
    float normal_twist;
    /*! Maximum acceptable "reverse" (higher bigger than lower) twist ratio. */
    float reverse_twist;
    /*! Minimum acceptable tone level for detection. */
    int32_t threshold;
    /*! The accumlating total energy on the same period over which the Goertzels work. */
    int32_t energy;
#else
    /*! 350Hz filter state for the optional dialtone filter. */
    float z350[2];
    /*! 440Hz filter state for the optional dialtone filter. */
    float z440[2];
    /*! Maximum acceptable "normal" (lower bigger than higher) twist ratio. */
    float normal_twist;
    /*! Maximum acceptable "reverse" (higher bigger than lower) twist ratio. */
    float reverse_twist;
    /*! Minimum acceptable tone level for detection. */
    float threshold;
    /*! The accumlating total energy on the same period over which the Goertzels work. */
    float energy;
#endif
    /*! Tone detector working states for the row tones. */
    goertzel_state_t row_out[4];
    /*! Tone detector working states for the column tones. */
    goertzel_state_t col_out[4];
    /*! The result of the last tone analysis. */
    uint8_t last_hit;
    /*! The confirmed digit we are currently receiving */
    uint8_t in_digit;
    /*! The current sample number within a processing block. */
    int current_sample;

    /*! The number of digits which have been lost due to buffer overflows. */
    int lost_digits;
    /*! The number of digits currently in the digit buffer. */
    int current_digits;
    /*! The received digits buffer. This is a NULL terminated string. */
    char digits[MAX_DTMF_DIGITS + 1];
};

#endif
/*- End of file ------------------------------------------------------------*/
