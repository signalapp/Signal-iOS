/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/super_tone_rx.h - Flexible telephony supervisory tone detection.
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
 * $Id: super_tone_rx.h,v 1.1 2008/11/30 10:17:31 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_SUPER_TONE_RX_H_)
#define _SPANDSP_PRIVATE_SUPER_TONE_RX_H_

#define BINS            128

struct super_tone_rx_segment_s
{
    int f1;
    int f2;
    int recognition_duration;
    int min_duration;
    int max_duration;
};

struct super_tone_rx_descriptor_s
{
    int used_frequencies;
    int monitored_frequencies;
    int pitches[BINS/2][2];
    int tones;
    super_tone_rx_segment_t **tone_list;
    int *tone_segs;
    goertzel_descriptor_t *desc;
};

struct super_tone_rx_state_s
{
    super_tone_rx_descriptor_t *desc;
    float energy;
    int detected_tone;
    int rotation;
    tone_report_func_t tone_callback;
    void (*segment_callback)(void *data, int f1, int f2, int duration);
    void *callback_data;
    super_tone_rx_segment_t segments[11];
    goertzel_state_t state[];
};

#endif
/*- End of file ------------------------------------------------------------*/
