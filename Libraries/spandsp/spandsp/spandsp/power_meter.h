/*
 * SpanDSP - a series of DSP components for telephony
 *
 * power_meter.h
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
 * $Id: power_meter.h,v 1.19 2009/05/19 14:15:09 steveu Exp $
 */

#if !defined(_POWER_METER_H_)
#define _POWER_METER_H_

/*! \page power_meter_page Power metering

\section power_meter_page_sec_1 What does it do?
The power metering module implements a simple IIR type running power meter. The damping
factor of the IIR is selectable when the meter instance is created.

Note that the definition of dBOv is quite vague in most places - is it peak since wave,
peak square wave, etc.? This code is based on the well defined wording in RFC3389:

"For example, in the case of a u-law system, the reference would be a square wave with
values +/-8031, and this square wave represents 0dBov.  This translates into 6.18dBm0".

\section power_meter_page_sec_2 How does it work?
*/

/*!
    Power meter descriptor. This defines the working state for a
    single instance of a power measurement device.
*/
typedef struct
{
    /*! The shift factor, which controls the damping of the power meter. */
    int shift;

    /*! The current power reading. */
    int32_t reading;
} power_meter_t;

typedef struct
{
    power_meter_t short_term;
    power_meter_t medium_term;
    int signal_present;
    int32_t surge;
    int32_t sag;
    int32_t min;
} power_surge_detector_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a power meter context.
    \brief Initialise a power meter context.
    \param s The power meter context.
    \param shift The shift to be used by the IIR filter.
    \return The power meter context. */
SPAN_DECLARE(power_meter_t *) power_meter_init(power_meter_t *s, int shift);

SPAN_DECLARE(int) power_meter_release(power_meter_t *s);

SPAN_DECLARE(int) power_meter_free(power_meter_t *s);

/*! Change the damping factor of a power meter context.
    \brief Change the damping factor of a power meter context.
    \param s The power meter context.
    \param shift The new shift to be used by the IIR filter.
    \return The power meter context. */
SPAN_DECLARE(power_meter_t *) power_meter_damping(power_meter_t *s, int shift);

/*! Update a power meter.
    \brief Update a power meter.
    \param s The power meter context.
    \param amp The amplitude of the new audio sample.
    \return The current power meter reading. */
SPAN_DECLARE(int32_t) power_meter_update(power_meter_t *s, int16_t amp);

/*! Get the current power meter reading.
    \brief Get the current power meter reading.
    \param s The power meter context.
    \return The current power meter reading. */
SPAN_DECLARE(int32_t) power_meter_current(power_meter_t *s);

/*! Get the current power meter reading, in dBm0.
    \brief Get the current power meter reading, in dBm0.
    \param s The power meter context.
    \return The current power meter reading, in dBm0. */
SPAN_DECLARE(float) power_meter_current_dbm0(power_meter_t *s);

/*! Get the current power meter reading, in dBOv.
    \brief Get the current power meter reading, in dBOv.
    \param s The power meter context.
    \return The current power meter reading, in dBOv. */
SPAN_DECLARE(float) power_meter_current_dbov(power_meter_t *s);

/*! Get the power meter reading which represents a specified power level in dBm0.
    \brief Get the current power meter reading, in dBm0.
    \param level A power level, in dB0m.
    \return The equivalent power meter reading. */
SPAN_DECLARE(int32_t) power_meter_level_dbm0(float level);

/*! Get the power meter reading which represents a specified power level in dBOv.
    \brief Get the current power meter reading, in dBOv.
    \param level A power level, in dBOv.
    \return The equivalent power meter reading. */
SPAN_DECLARE(int32_t) power_meter_level_dbov(float level);

SPAN_DECLARE(int32_t) power_surge_detector(power_surge_detector_state_t *s, int16_t amp);

/*! Get the current surge detector short term meter reading, in dBm0.
    \brief Get the current surge detector meter reading, in dBm0.
    \param s The power surge detector context.
    \return The current power surge detector power reading, in dBm0. */
SPAN_DECLARE(float) power_surge_detector_current_dbm0(power_surge_detector_state_t *s);

/*! Get the current surge detector short term meter reading, in dBOv.
    \brief Get the current surge detector meter reading, in dBOv.
    \param s The power surge detector context.
    \return The current power surge detector power reading, in dBOv. */
SPAN_DECLARE(float) power_surge_detector_current_dbov(power_surge_detector_state_t *s);

SPAN_DECLARE(power_surge_detector_state_t *) power_surge_detector_init(power_surge_detector_state_t *s, float min, float surge);

SPAN_DECLARE(int) power_surge_detector_release(power_surge_detector_state_t *s);

SPAN_DECLARE(int) power_surge_detector_free(power_surge_detector_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
