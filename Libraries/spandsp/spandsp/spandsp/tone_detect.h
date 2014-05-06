/*
 * SpanDSP - a series of DSP components for telephony
 *
 * tone_detect.h - General telephony tone detection.
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
 * $Id: tone_detect.h,v 1.45 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_TONE_DETECT_H_)
#define _SPANDSP_TONE_DETECT_H_

/*!
    Goertzel filter descriptor.
*/
struct goertzel_descriptor_s
{
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t fac;
#else
    float fac;
#endif
    int samples;
};

/*!
    Goertzel filter state descriptor.
*/
struct goertzel_state_s
{
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t v2;
    int16_t v3;
    int16_t fac;
#else
    float v2;
    float v3;
    float fac;
#endif
    int samples;
    int current_sample;
};

/*!
    Goertzel filter descriptor.
*/
typedef struct goertzel_descriptor_s goertzel_descriptor_t;

/*!
    Goertzel filter state descriptor.
*/
typedef struct goertzel_state_s goertzel_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Create a descriptor for use with either a Goertzel transform */
SPAN_DECLARE(void) make_goertzel_descriptor(goertzel_descriptor_t *t,
                                            float freq,
                                            int samples);

/*! \brief Initialise the state of a Goertzel transform.
    \param s The Goertzel context. If NULL, a context is allocated with malloc.
    \param t The Goertzel descriptor.
    \return A pointer to the Goertzel state. */
SPAN_DECLARE(goertzel_state_t *) goertzel_init(goertzel_state_t *s,
                                               goertzel_descriptor_t *t);

SPAN_DECLARE(int) goertzel_release(goertzel_state_t *s);

SPAN_DECLARE(int) goertzel_free(goertzel_state_t *s);

/*! \brief Reset the state of a Goertzel transform.
    \param s The Goertzel context. */
SPAN_DECLARE(void) goertzel_reset(goertzel_state_t *s);

/*! \brief Update the state of a Goertzel transform.
    \param s The Goertzel context.
    \param amp The samples to be transformed.
    \param samples The number of samples.
    \return The number of samples unprocessed */
SPAN_DECLARE(int) goertzel_update(goertzel_state_t *s,
                                  const int16_t amp[],
                                  int samples);

/*! \brief Evaluate the final result of a Goertzel transform.
    \param s The Goertzel context.
    \return The result of the transform. The expected result for a pure sine wave
            signal of level x dBm0, at the very centre of the bin is:
    [Floating point] ((samples_per_goertzel_block*32768.0/1.4142)*10^((x - DBM0_MAX_SINE_POWER)/20.0))^2
    [Fixed point] ((samples_per_goertzel_block*256.0/1.4142)*10^((x - DBM0_MAX_SINE_POWER)/20.0))^2 */
#if defined(SPANDSP_USE_FIXED_POINT)
SPAN_DECLARE(int32_t) goertzel_result(goertzel_state_t *s);
#else
SPAN_DECLARE(float) goertzel_result(goertzel_state_t *s);
#endif

/*! \brief Update the state of a Goertzel transform.
    \param s The Goertzel context.
    \param amp The sample to be transformed. */
static __inline__ void goertzel_sample(goertzel_state_t *s, int16_t amp)
{
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t x;
    int16_t v1;
#else
    float v1;
#endif

    v1 = s->v2;
    s->v2 = s->v3;
#if defined(SPANDSP_USE_FIXED_POINT)
    x = (((int32_t) s->fac*s->v2) >> 14);
    /* Scale down the input signal to avoid overflows. 9 bits is enough to
       monitor the signals of interest with adequate dynamic range and
       resolution. In telephony we generally only start with 13 or 14 bits,
       anyway. */
    s->v3 = x - v1 + (amp >> 7);
#else
    s->v3 = s->fac*s->v2 - v1 + amp;
#endif
    s->current_sample++;
}
/*- End of function --------------------------------------------------------*/

/* Scale down the input signal to avoid overflows. 9 bits is enough to
   monitor the signals of interest with adequate dynamic range and
   resolution. In telephony we generally only start with 13 or 14 bits,
   anyway. This is sufficient for the longest Goertzel we currently use. */
#if defined(SPANDSP_USE_FIXED_POINT)
#define goertzel_preadjust_amp(amp) (((int16_t) amp) >> 7)
#else
#define goertzel_preadjust_amp(amp) ((float) amp)
#endif

/* Minimal update the state of a Goertzel transform. This is similar to
   goertzel_sample, but more suited to blocks of Goertzels. It assumes
   the amplitude is pre-shifted, and does not update the per-state sample
   count.
    \brief Update the state of a Goertzel transform.
    \param s The Goertzel context.
    \param amp The adjusted sample to be transformed. */
#if defined(SPANDSP_USE_FIXED_POINT)
static __inline__ void goertzel_samplex(goertzel_state_t *s, int16_t amp)
#else
static __inline__ void goertzel_samplex(goertzel_state_t *s, float amp)
#endif
{
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t x;
    int16_t v1;
#else
    float v1;
#endif

    v1 = s->v2;
    s->v2 = s->v3;
#if defined(SPANDSP_USE_FIXED_POINT)
    x = (((int32_t) s->fac*s->v2) >> 14);
    s->v3 = x - v1 + amp;
#else
    s->v3 = s->fac*s->v2 - v1 + amp;
#endif
}
/*- End of function --------------------------------------------------------*/

/*! Generate a Hamming weighted coefficient set, to be used for a periodogram analysis.
    \param coeffs The generated coefficients.
    \param freq The frequency to be matched by the periodogram, in Hz.
    \param sample_rate The sample rate of the signal, in samples per second.
    \param window_len The length of the periodogram window. This must be an even number.
    \return The number of generated coefficients.
*/
SPAN_DECLARE(int) periodogram_generate_coeffs(complexf_t coeffs[], float freq, int sample_rate, int window_len);

/*! Generate the phase offset to be expected between successive periodograms evaluated at the 
    specified interval.
    \param offset A point to the generated phase offset.
    \param freq The frequency being matched by the periodogram, in Hz.
    \param sample_rate The sample rate of the signal, in samples per second.
    \param interval The interval between periodograms, in samples.
    \return The scaling factor.
*/
SPAN_DECLARE(float) periodogram_generate_phase_offset(complexf_t *offset, float freq, int sample_rate, int interval);

/*! Evaluate a periodogram.
    \param coeffs A set of coefficients generated by periodogram_generate_coeffs().
    \param amp The complex amplitude of the signal.
    \param len The length of the periodogram, in samples. This must be an even number.
    \return The periodogram result.
*/
SPAN_DECLARE(complexf_t) periodogram(const complexf_t coeffs[], const complexf_t amp[], int len);

/*! Prepare data for evaluating a set of periodograms.
    \param sum A vector of sums of pairs of signal samples. This will be half the length of len.
    \param diff A vector of differences between pairs of signal samples. This will be half the length of len.
    \param amp The complex amplitude of the signal.
    \param len The length of the periodogram, in samples. This must be an even number.
    \return The length of the vectors sum and diff.
*/
SPAN_DECLARE(int) periodogram_prepare(complexf_t sum[], complexf_t diff[], const complexf_t amp[], int len);

/*! Evaluate a periodogram, based on data prepared by periodogram_prepare(). This is more efficient
    than using periodogram() when several periodograms are to be applied to the same signal.
    \param coeffs A set of coefficients generated by periodogram_generate_coeffs().
    \param sum A vector of sums produced by periodogram_prepare().
    \param diff A vector of differences produced by periodogram_prepare().
    \param len The length of the periodogram, in samples. This must be an even number.
    \return The periodogram result.
*/
SPAN_DECLARE(complexf_t) periodogram_apply(const complexf_t coeffs[], const complexf_t sum[], const complexf_t diff[], int len);

/*! Apply a phase offset, to find the frequency error between periodogram evaluations.
    specified interval.
    \param phase_offset A point to the expected phase offset.
    \param scale The scaling factor to be used.
    \param last_result A pointer to the previous periodogram result.
    \param result A pointer to the current periodogram result.
    \return The frequency error, in Hz.
*/
SPAN_DECLARE(float) periodogram_freq_error(const complexf_t *phase_offset, float scale, const complexf_t *last_result, const complexf_t *result);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
