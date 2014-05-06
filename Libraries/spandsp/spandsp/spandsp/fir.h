/*
 * SpanDSP - a series of DSP components for telephony
 *
 * fir.h - General telephony FIR routines
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2002 Steve Underwood
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
 * $Id: fir.h,v 1.13 2008/04/17 14:27:00 steveu Exp $
 */

/*! \page fir_page FIR filtering
\section fir_page_sec_1 What does it do?
???.

\section fir_page_sec_2 How does it work?
???.
*/

#if !defined(_SPANDSP_FIR_H_)
#define _SPANDSP_FIR_H_

#if defined(USE_MMX)  ||  defined(USE_SSE2)
#include "mmx.h"
#endif

/*!
    16 bit integer FIR descriptor. This defines the working state for a single
    instance of an FIR filter using 16 bit integer coefficients.
*/
typedef struct
{
    int taps;
    int curr_pos;
    const int16_t *coeffs;
    int16_t *history;
} fir16_state_t;

/*!
    32 bit integer FIR descriptor. This defines the working state for a single
    instance of an FIR filter using 32 bit integer coefficients, and filtering
    16 bit integer data.
*/
typedef struct
{
    int taps;
    int curr_pos;
    const int32_t *coeffs;
    int16_t *history;
} fir32_state_t;

/*!
    Floating point FIR descriptor. This defines the working state for a single
    instance of an FIR filter using floating point coefficients and data.
*/
typedef struct
{
    int taps;
    int curr_pos;
    const float *coeffs;
    float *history;
} fir_float_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

static __inline__ const int16_t *fir16_create(fir16_state_t *fir,
                                              const int16_t *coeffs,
                                              int taps)
{
    fir->taps = taps;
    fir->curr_pos = taps - 1;
    fir->coeffs = coeffs;
#if defined(USE_MMX)  ||  defined(USE_SSE2)
    if ((fir->history = malloc(2*taps*sizeof(int16_t))))
        memset(fir->history, 0, 2*taps*sizeof(int16_t));
#else
    if ((fir->history = (int16_t *) malloc(taps*sizeof(int16_t))))
        memset(fir->history, 0, taps*sizeof(int16_t));
#endif
    return fir->history;
}
/*- End of function --------------------------------------------------------*/

static __inline__ void fir16_flush(fir16_state_t *fir)
{
#if defined(USE_MMX)  ||  defined(USE_SSE2)
    memset(fir->history, 0, 2*fir->taps*sizeof(int16_t));
#else
    memset(fir->history, 0, fir->taps*sizeof(int16_t));
#endif
}
/*- End of function --------------------------------------------------------*/

static __inline__ void fir16_free(fir16_state_t *fir)
{
    free(fir->history);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t fir16(fir16_state_t *fir, int16_t sample)
{
    int i;
    int32_t y;
#if defined(USE_MMX)
    mmx_t *mmx_coeffs;
    mmx_t *mmx_hist;

    fir->history[fir->curr_pos] = sample;
    fir->history[fir->curr_pos + fir->taps] = sample;

    mmx_coeffs = (mmx_t *) fir->coeffs;
    mmx_hist = (mmx_t *) &fir->history[fir->curr_pos];
    i = fir->taps;
    pxor_r2r(mm4, mm4);
    /* 8 samples per iteration, so the filter must be a multiple of 8 long. */
    while (i > 0)
    {
        movq_m2r(mmx_coeffs[0], mm0);
        movq_m2r(mmx_coeffs[1], mm2);
        movq_m2r(mmx_hist[0], mm1);
        movq_m2r(mmx_hist[1], mm3);
        mmx_coeffs += 2;
        mmx_hist += 2;
        pmaddwd_r2r(mm1, mm0);
        pmaddwd_r2r(mm3, mm2);
        paddd_r2r(mm0, mm4);
        paddd_r2r(mm2, mm4);
        i -= 8;
    }
    movq_r2r(mm4, mm0);
    psrlq_i2r(32, mm0);
    paddd_r2r(mm0, mm4);
    movd_r2m(mm4, y);
    emms();
#elif defined(USE_SSE2)
    xmm_t *xmm_coeffs;
    xmm_t *xmm_hist;

    fir->history[fir->curr_pos] = sample;
    fir->history[fir->curr_pos + fir->taps] = sample;

    xmm_coeffs = (xmm_t *) fir->coeffs;
    xmm_hist = (xmm_t *) &fir->history[fir->curr_pos];
    i = fir->taps;
    pxor_r2r(xmm4, xmm4);
    /* 16 samples per iteration, so the filter must be a multiple of 16 long. */
    while (i > 0)
    {
        movdqu_m2r(xmm_coeffs[0], xmm0);
        movdqu_m2r(xmm_coeffs[1], xmm2);
        movdqu_m2r(xmm_hist[0], xmm1);
        movdqu_m2r(xmm_hist[1], xmm3);
        xmm_coeffs += 2;
        xmm_hist += 2;
        pmaddwd_r2r(xmm1, xmm0);
        pmaddwd_r2r(xmm3, xmm2);
        paddd_r2r(xmm0, xmm4);
        paddd_r2r(xmm2, xmm4);
        i -= 16;
    }
    movdqa_r2r(xmm4, xmm0);
    psrldq_i2r(8, xmm0);
    paddd_r2r(xmm0, xmm4);
    movdqa_r2r(xmm4, xmm0);
    psrldq_i2r(4, xmm0);
    paddd_r2r(xmm0, xmm4);
    movd_r2m(xmm4, y);
#else
    int offset1;
    int offset2;

    fir->history[fir->curr_pos] = sample;

    offset2 = fir->curr_pos;
    offset1 = fir->taps - offset2;
    y = 0;
    for (i = fir->taps - 1;  i >= offset1;  i--)
        y += fir->coeffs[i]*fir->history[i - offset1];
    for (  ;  i >= 0;  i--)
        y += fir->coeffs[i]*fir->history[i + offset2];
#endif
    if (fir->curr_pos <= 0)
    	fir->curr_pos = fir->taps;
    fir->curr_pos--;
    return (int16_t) (y >> 15);
}
/*- End of function --------------------------------------------------------*/

static __inline__ const int16_t *fir32_create(fir32_state_t *fir,
                                              const int32_t *coeffs,
                                              int taps)
{
    fir->taps = taps;
    fir->curr_pos = taps - 1;
    fir->coeffs = coeffs;
    fir->history = (int16_t *) malloc(taps*sizeof(int16_t));
    if (fir->history)
    	memset(fir->history, '\0', taps*sizeof(int16_t));
    return fir->history;
}
/*- End of function --------------------------------------------------------*/

static __inline__ void fir32_flush(fir32_state_t *fir)
{
    memset(fir->history, 0, fir->taps*sizeof(int16_t));
}
/*- End of function --------------------------------------------------------*/

static __inline__ void fir32_free(fir32_state_t *fir)
{
    free(fir->history);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t fir32(fir32_state_t *fir, int16_t sample)
{
    int i;
    int32_t y;
    int offset1;
    int offset2;

    fir->history[fir->curr_pos] = sample;
    offset2 = fir->curr_pos;
    offset1 = fir->taps - offset2;
    y = 0;
    for (i = fir->taps - 1;  i >= offset1;  i--)
        y += fir->coeffs[i]*fir->history[i - offset1];
    for (  ;  i >= 0;  i--)
        y += fir->coeffs[i]*fir->history[i + offset2];
    if (fir->curr_pos <= 0)
    	fir->curr_pos = fir->taps;
    fir->curr_pos--;
    return (int16_t) (y >> 15);
}
/*- End of function --------------------------------------------------------*/

static __inline__ const float *fir_float_create(fir_float_state_t *fir,
                                                const float *coeffs,
    	    	    	                        int taps)
{
    fir->taps = taps;
    fir->curr_pos = taps - 1;
    fir->coeffs = coeffs;
    fir->history = (float *) malloc(taps*sizeof(float));
    if (fir->history)
        memset(fir->history, '\0', taps*sizeof(float));
    return fir->history;
}
/*- End of function --------------------------------------------------------*/
    
static __inline__ void fir_float_free(fir_float_state_t *fir)
{
    free(fir->history);
}
/*- End of function --------------------------------------------------------*/

static __inline__ int16_t fir_float(fir_float_state_t *fir, int16_t sample)
{
    int i;
    float y;
    int offset1;
    int offset2;

    fir->history[fir->curr_pos] = sample;

    offset2 = fir->curr_pos;
    offset1 = fir->taps - offset2;
    y = 0;
    for (i = fir->taps - 1;  i >= offset1;  i--)
        y += fir->coeffs[i]*fir->history[i - offset1];
    for (  ;  i >= 0;  i--)
        y += fir->coeffs[i]*fir->history[i + offset2];
    if (fir->curr_pos <= 0)
    	fir->curr_pos = fir->taps;
    fir->curr_pos--;
    return  (int16_t) y;
}
/*- End of function --------------------------------------------------------*/

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
