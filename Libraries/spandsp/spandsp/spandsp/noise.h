/*
 * SpanDSP - a series of DSP components for telephony
 *
 * noise.h - A low complexity audio noise generator, suitable for
 *           real time generation (current just approx AWGN)
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005 Steve Underwood
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
 * $Id: noise.h,v 1.17 2009/02/10 13:06:47 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_NOISE_H_)
#define _SPANDSP_NOISE_H_

/*! \page noise_page Noise generation

\section noise_page_sec_1 What does it do?
It generates audio noise. Currently it only generates reasonable quality
AWGN. It is designed to be of sufficiently low complexity to generate large
volumes of reasonable quality noise, in real time.

Hoth noise is used to model indoor ambient noise when evaluating communications
systems such as telephones. It is named after D.F. Hoth, who made the first 
systematic study of this. The official definition of Hoth noise is IEEE
standard 269-2001 (revised from 269-1992), "Draft Standard Methods for Measuring
Transmission Performance of Analog and Digital Telephone Sets, Handsets and Headsets."

The table below gives the spectral density of Hoth noise, adjusted in level to produce
a reading of 50 dBA.

Freq (Hz)  Spectral     Bandwidth       Total power in
           density      10 log_f        each 1/3 octave band
           (dB SPL/Hz)  (dB)            (dB SPL)
 100        32.4        13.5            45.9
 125        30.9        14.7            45.5
 160        29.1        15.7            44.9
 200        27.6        16.5            44.1
 250        26.0        17.6            43.6
 315        24.4        18.7            43.1
 400        22.7        19.7            42.3
 500        21.1        20.6            41.7
 630        19.5        21.7            41.2
 800        17.8        22.7            40.4
1000        16.2        23.5            39.7
1250        14.6        24.7            39.3
1600        12.9        25.7            38.7
2000        11.3        26.5            37.8
2500         9.6        27.6            37.2
3150         7.8        28.7            36.5
4000         5.4        29.7            34.8
5000         2.6        30.6            33.2
6300        -1.3        31.7            30.4
8000        -6.6        32.7            26.0

The tolerance for each 1/3rd octave band is กำ3dB.

\section awgn_page_sec_2 How does it work?
The central limit theorem says if you add a few random numbers together,
the result starts to look Gaussian. In this case we sum 8 random numbers.
The result is fast, and perfectly good as a noise source for many purposes.
It should not be trusted as a high quality AWGN generator, for elaborate
modelling purposes.
*/

enum
{
    NOISE_CLASS_AWGN = 1,
    NOISE_CLASS_HOTH
};

/*!
    Noise generator descriptor. This contains all the state information for an instance
    of the noise generator.
 */
typedef struct noise_state_s noise_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise an audio noise generator.
    \brief Initialise an audio noise generator.
    \param s The noise generator context.
    \param seed A seed for the underlying random number generator.
    \param level The noise power level in dBmO.
    \param class_of_noise The class of noise (e.g. AWGN).
    \param quality A parameter which permits speed and accuracy of the noise
           generation to be adjusted.
    \return A pointer to the noise generator context.
*/
SPAN_DECLARE(noise_state_t *) noise_init_dbm0(noise_state_t *s, int seed, float level, int class_of_noise, int quality);

SPAN_DECLARE(noise_state_t *) noise_init_dbov(noise_state_t *s, int seed, float level, int class_of_noise, int quality);

SPAN_DECLARE(int) noise_release(noise_state_t *s);

SPAN_DECLARE(int) noise_free(noise_state_t *s);

/*! Generate a sample of audio noise.
    \brief Generate a sample of audio noise.
    \param s The noise generator context.
    \return The generated sample.
*/
SPAN_DECLARE(int16_t) noise(noise_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
