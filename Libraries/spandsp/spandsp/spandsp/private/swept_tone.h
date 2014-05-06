/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/swept_tone.h - Swept tone generation
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2009 Steve Underwood
 *
 * All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2, as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * $Id: swept_tone.h,v 1.1 2009/09/22 12:54:33 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_SWEPT_TONE_H_)
#define _SPANDSP_PRIVATE_SWEPT_TONE_H_

struct swept_tone_state_s
{
    int32_t starting_phase_inc;
    int32_t phase_inc_step;
    int scale;
    int duration;
    int repeating;
    int pos;
    int32_t current_phase_inc;
    uint32_t phase;
};

#endif
/*- End of file ------------------------------------------------------------*/
