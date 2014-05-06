/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/modem_connect_tones.c - Generation and detection of tones
 *                                 associated with modems calling and
 *                                 answering calls.
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
 * $Id: modem_connect_tones.h,v 1.3 2009/11/02 13:25:20 steveu Exp $
 */
 
/*! \file */

#if !defined(_SPANDSP_PRIVATE_MODEM_CONNECT_TONES_H_)
#define _SPANDSP_PRIVATE_MODEM_CONNECT_TONES_H_

/*!
    Modem connect tones generator descriptor. This defines the state
    of a single working instance of the tone generator.
*/
struct modem_connect_tones_tx_state_s
{
    int tone_type;

    int32_t tone_phase_rate;
    uint32_t tone_phase;
    int16_t level;
    /*! \brief Countdown to the next phase hop */
    int hop_timer;
    /*! \brief Maximum duration timer */
    int duration_timer;
    uint32_t mod_phase;
    int32_t mod_phase_rate;
    int16_t mod_level;
};

/*!
    Modem connect tones receiver descriptor. This defines the state
    of a single working instance of the tone detector.
*/
struct modem_connect_tones_rx_state_s
{
    /*! \brief The tone type being detected. */
    int tone_type;
    /*! \brief Callback routine, using to report detection of the tone. */
    tone_report_func_t tone_callback;
    /*! \brief An opaque pointer passed to tone_callback. */
    void *callback_data;

    /*! \brief The notch filter state. */
    float znotch_1;
    float znotch_2;
    /*! \brief The 15Hz AM  filter state. */
    float z15hz_1;
    float z15hz_2;
    /*! \brief The in notch power estimate */
    int32_t notch_level;
    /*! \brief The total channel power estimate */
    int32_t channel_level;
    /*! \brief The 15Hz AM power estimate */
    int32_t am_level;
    /*! \brief Sample counter for the small chunks of samples, after which a test is conducted. */
    int chunk_remainder;
    /*! \brief TRUE is the tone is currently confirmed present in the audio. */
    int tone_present;
    /*! \brief */
    int tone_on;
    /*! \brief A millisecond counter, to time the duration of tone sections. */
    int tone_cycle_duration;
    /*! \brief A count of the number of good cycles of tone reversal seen. */
    int good_cycles;
    /*! \brief TRUE if the tone has been seen since the last time the user tested for it */
    int hit;
    /*! \brief A V.21 FSK modem context used when searching for FAX preamble. */
    fsk_rx_state_t v21rx;
    /*! \brief The raw (stuffed) bit stream buffer. */
    unsigned int raw_bit_stream;
    /*! \brief The current number of bits in the octet in progress. */
    int num_bits;
    /*! \brief Number of consecutive flags seen so far. */
    int flags_seen;
    /*! \brief TRUE if framing OK has been announced. */
    int framing_ok_announced;
};

#endif
/*- End of file ------------------------------------------------------------*/
