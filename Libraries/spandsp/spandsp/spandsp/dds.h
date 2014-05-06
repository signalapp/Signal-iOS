/*
 * SpanDSP - a series of DSP components for telephony
 *
 * dds.h
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
 * $Id: dds.h,v 1.23 2009/01/31 08:48:11 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_DDS_H_)
#define _SPANDSP_DDS_H_

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Find the phase rate value to achieve a particular frequency.
    \param frequency The desired frequency, in Hz.
    \return The phase rate which while achieve the desired frequency.
*/
SPAN_DECLARE(int32_t) dds_phase_rate(float frequency);

/*! \brief Find the frequency, in Hz, equivalent to a phase rate.
    \param phase_rate The phase rate.
    \return The equivalent frequency, in Hz.
*/
SPAN_DECLARE(float) dds_frequency(int32_t phase_rate);

/*! \brief Find the scaling factor needed to achieve a specified level in dBm0.
    \param level The desired signal level, in dBm0.
    \return The scaling factor.
*/
SPAN_DECLARE(int16_t) dds_scaling_dbm0(float level);

/*! \brief Find the scaling factor needed to achieve a specified level in dBmov.
    \param level The desired signal level, in dBmov.
    \return The scaling factor.
*/
SPAN_DECLARE(int16_t) dds_scaling_dbov(float level);

/*! \brief Find the amplitude for a particular phase.
    \param phase The desired phase 32 bit phase.
    \return The signal amplitude.
*/
SPAN_DECLARE(int16_t) dds_lookup(uint32_t phase);

/*! \brief Find the amplitude for a particular phase offset from an accumulated phase.
    \param phase_acc The accumulated phase.
    \param phase_offset The phase offset.
    \return The signal amplitude.
*/
SPAN_DECLARE(int16_t) dds_offset(uint32_t phase_acc, int32_t phase_offset);

/*! \brief Advance the phase, without returning any new signal sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
*/
SPAN_DECLARE(void) dds_advance(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Generate an integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The signal amplitude, between -32767 and 32767.
*/
SPAN_DECLARE(int16_t) dds(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Lookup the integer value of a specified phase.
    \param phase The phase accumulator value to be looked up.
    \return The signal amplitude, between -32767 and 32767.
*/
SPAN_DECLARE(int16_t) dds_lookup(uint32_t phase);

/*! \brief Generate an integer tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The signal amplitude, between -32767 and 32767.
*/
SPAN_DECLARE(int16_t) dds_mod(uint32_t *phase_acc, int32_t phase_rate, int16_t scale, int32_t phase);

/*! \brief Lookup the complex integer value of a specified phase.
    \param phase The phase accumulator value to be looked up.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi_t) dds_lookup_complexi(uint32_t phase);

/*! \brief Generate a complex integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi_t) dds_complexi(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Generate a complex integer tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi_t) dds_complexi_mod(uint32_t *phase_acc, int32_t phase_rate, int16_t scale, int32_t phase);

/*! \brief Generate a complex 16 bit integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi16_t) dds_lookup_complexi16(uint32_t phase);

/*! \brief Generate a complex 16 bit integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi16_t) dds_complexi16(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Generate a complex 16bit integer tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi16_t) dds_complexi16_mod(uint32_t *phase_acc, int32_t phase_rate, int16_t scale, int32_t phase);

/*! \brief Generate a complex 32 bit integer tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi32_t) dds_complexi32_mod(uint32_t *phase_acc, int32_t phase_rate, int16_t scale, int32_t phase);

/*! \brief Generate a complex 32 bit integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi32_t) dds_lookup_complexi32(uint32_t phase);

/*! \brief Generate a complex 32 bit integer tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi32_t) dds_complexi32(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Generate a complex 32 bit integer tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The complex signal amplitude, between (-32767, -32767) and (32767, 32767).
*/
SPAN_DECLARE(complexi32_t) dds_complexi32_mod(uint32_t *phase_acc, int32_t phase_rate, int16_t scale, int32_t phase);

/*! \brief Find the phase rate equivalent to a frequency, in Hz.
    \param frequency The frequency, in Hz.
    \return The equivalent phase rate.
*/
SPAN_DECLARE(int32_t) dds_phase_ratef(float frequency);

/*! \brief Find the frequency, in Hz, equivalent to a phase rate.
    \param phase_rate The phase rate.
    \return The equivalent frequency, in Hz.
*/
SPAN_DECLARE(float) dds_frequencyf(int32_t phase_rate);

/*! \brief Find the scaling factor equivalent to a dBm0 value.
    \param level The signal level in dBm0.
    \return The equivalent scaling factor.
*/
SPAN_DECLARE(float) dds_scaling_dbm0f(float level);

/*! \brief Find the scaling factor equivalent to a dBmov value.
    \param level The signal level in dBmov.
    \return The equivalent scaling factor.
*/
SPAN_DECLARE(float) dds_scaling_dbovf(float level);

/*! \brief Advance the phase, without returning any new signal sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
*/
SPAN_DECLARE(void) dds_advancef(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Generate a floating point tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The signal amplitude, between -1.0 and 1.0.
*/
SPAN_DECLARE(float) ddsf(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Lookup the floating point value of a specified phase.
    \param phase The phase accumulator value to be looked up.
    \return The signal amplitude, between -1.0 and 1.0.
*/
SPAN_DECLARE(float) dds_lookupf(uint32_t phase);

/*! \brief Generate a floating point tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The signal amplitude, between -1.0 and 1.0.
*/
SPAN_DECLARE(float) dds_modf(uint32_t *phase_acc, int32_t phase_rate, float scale, int32_t phase);

/*! \brief Generate a complex floating point tone sample.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \return The complex signal amplitude, between (-1.0, -1.0) and (1.0, 1.0).
*/
SPAN_DECLARE(complexf_t) dds_complexf(uint32_t *phase_acc, int32_t phase_rate);

/*! \brief Lookup the complex value of a specified phase.
    \param phase The phase accumulator value to be looked up.
    \return The complex signal amplitude, between (-1.0, -1.0) and (1.0, 1.0).
*/
SPAN_DECLARE(complexf_t) dds_lookup_complexf(uint32_t phase_acc);

/*! \brief Generate a complex floating point tone sample, with modulation.
    \param phase_acc A pointer to a phase accumulator value.
    \param phase_rate The phase increment to be applied.
    \param scale The scaling factor.
    \param phase The phase offset.
    \return The complex signal amplitude, between (-1.0, -1.0) and (1.0, 1.0).
*/
SPAN_DECLARE(complexf_t) dds_complex_modf(uint32_t *phase_acc, int32_t phase_rate, float scale, int32_t phase);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
