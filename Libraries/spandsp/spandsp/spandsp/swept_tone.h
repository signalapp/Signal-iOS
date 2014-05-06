/*
 * SpanDSP - a series of DSP components for telephony
 *
 * swept_tone.h - Swept tone generation
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

/*! \file */

#if !defined(_SPANDSP_SWEPT_TONE_H_)
#define _SPANDSP_SWEPT_TONE_H_

/*! \page swept_tone_page The swept tone generator
\section swept_tone_page_sec_1 What does it do?
*/

typedef struct swept_tone_state_s swept_tone_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(swept_tone_state_t *) swept_tone_init(swept_tone_state_t *s, float start, float end, float level, int duration, int repeating);

SPAN_DECLARE(int) swept_tone(swept_tone_state_t *s, int16_t amp[], int len);

SPAN_DECLARE(float) swept_tone_current_frequency(swept_tone_state_t *s);

SPAN_DECLARE(int) swept_tone_release(swept_tone_state_t *s);

SPAN_DECLARE(int) swept_tone_free(swept_tone_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
