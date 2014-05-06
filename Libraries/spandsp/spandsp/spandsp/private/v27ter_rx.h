/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v27ter_rx.h - ITU V.27ter modem receive part
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
 * $Id: v27ter_rx.h,v 1.2 2009/07/09 13:52:09 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_V27TER_RX_H_)
#define _SPANDSP_PRIVATE_V27TER_RX_H_

/* Target length for the equalizer is about 43 taps for 4800bps and 32 taps for 2400bps
   to deal with the worst stuff in V.56bis. */
/*! Samples before the target position in the equalizer buffer */
#define V27TER_EQUALIZER_PRE_LEN        16  /* This much before the real event */
/*! Samples after the target position in the equalizer buffer */
#define V27TER_EQUALIZER_POST_LEN       14  /* This much after the real event (must be even) */

/*! The number of taps in the 4800bps pulse shaping/bandpass filter */
#define V27TER_RX_4800_FILTER_STEPS     27
/*! The number of taps in the 2400bps pulse shaping/bandpass filter */
#define V27TER_RX_2400_FILTER_STEPS     27

#if V27TER_RX_4800_FILTER_STEPS > V27TER_RX_2400_FILTER_STEPS
#define V27TER_RX_FILTER_STEPS V27TER_RX_4800_FILTER_STEPS
#else
#define V27TER_RX_FILTER_STEPS V27TER_RX_2400_FILTER_STEPS
#endif

/*!
    V.27ter modem receive side descriptor. This defines the working state for a
    single instance of a V.27ter modem receiver.
*/
struct v27ter_rx_state_s
{
    /*! \brief The bit rate of the modem. Valid values are 2400 and 4800. */
    int bit_rate;
    /*! \brief The callback function used to put each bit received. */
    put_bit_func_t put_bit;
    /*! \brief A user specified opaque pointer passed to the put_bit routine. */
    void *put_bit_user_data;

    /*! \brief The callback function used to report modem status changes. */
    modem_rx_status_func_t status_handler;
    /*! \brief A user specified opaque pointer passed to the status function. */
    void *status_user_data;

    /*! \brief A callback function which may be enabled to report every symbol's
               constellation position. */
    qam_report_handler_t qam_report;
    /*! \brief A user specified opaque pointer passed to the qam_report callback
               routine. */
    void *qam_user_data;

    /*! \brief The route raised cosine (RRC) pulse shaping filter buffer. */
#if defined(SPANDSP_USE_FIXED_POINT)
    int16_t rrc_filter[V27TER_RX_FILTER_STEPS];
#else
    float rrc_filter[V27TER_RX_FILTER_STEPS];
#endif
    /*! \brief Current offset into the RRC pulse shaping filter buffer. */
    int rrc_filter_step;

    /*! \brief The register for the training and data scrambler. */
    unsigned int scramble_reg;
    /*! \brief A counter for the number of consecutive bits of repeating pattern through
               the scrambler. */
    int scrambler_pattern_count;
    /*! \brief The current step in the table of BC constellation positions. */
    int training_bc;
    /*! \brief TRUE if the previous trained values are to be reused. */
    int old_train;
    /*! \brief The section of the training data we are currently in. */
    int training_stage;
    /*! \brief A count of how far through the current training step we are. */
    int training_count;
    /*! \brief A measure of how much mismatch there is between the real constellation,
        and the decoded symbol positions. */
    float training_error;
    /*! \brief The value of the last signal sample, using the a simple HPF for signal power estimation. */
    int16_t last_sample;
    /*! \brief >0 if a signal above the minimum is present. It may or may not be a V.27ter signal. */
    int signal_present;
    /*! \brief Whether or not a carrier drop was detected and the signal delivery is pending. */
    int carrier_drop_pending;
    /*! \brief A count of the current consecutive samples below the carrier off threshold. */
    int low_samples;
    /*! \brief A highest magnitude sample seen. */
    int16_t high_sample;

    /*! \brief The position of the current symbol in the constellation, used for
               differential decoding. */
    int constellation_state;

    /*! \brief The current phase of the carrier (i.e. the DDS parameter). */
    uint32_t carrier_phase;
    /*! \brief The update rate for the phase of the carrier (i.e. the DDS increment). */
    int32_t carrier_phase_rate;
    /*! \brief The carrier update rate saved for reuse when using short training. */
    int32_t carrier_phase_rate_save;
#if defined(SPANDSP_USE_FIXED_POINTx)
    /*! \brief The proportional part of the carrier tracking filter. */
    float carrier_track_p;
    /*! \brief The integral part of the carrier tracking filter. */
    float carrier_track_i;
#else
    /*! \brief The proportional part of the carrier tracking filter. */
    float carrier_track_p;
    /*! \brief The integral part of the carrier tracking filter. */
    float carrier_track_i;
#endif

    /*! \brief A power meter, to measure the HPF'ed signal power in the channel. */    
    power_meter_t power;
    /*! \brief The power meter level at which carrier on is declared. */
    int32_t carrier_on_power;
    /*! \brief The power meter level at which carrier off is declared. */
    int32_t carrier_off_power;

    /*! \brief Current read offset into the equalizer buffer. */
    int eq_step;
    /*! \brief Current write offset into the equalizer buffer. */
    int eq_put_step;
    /*! \brief Symbol counter to the next equalizer update. */
    int eq_skip;

    /*! \brief The current half of the baud. */
    int baud_half;

#if defined(SPANDSP_USE_FIXED_POINT)
    /*! \brief The scaling factor accessed by the AGC algorithm. */
    int16_t agc_scaling;
    /*! \brief The previous value of agc_scaling, needed to reuse old training. */
    int16_t agc_scaling_save;

    /*! \brief The current delta factor for updating the equalizer coefficients. */
    float eq_delta;
    /*! \brief The adaptive equalizer coefficients. */
    /*complexi16_t*/ complexf_t  eq_coeff[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
    /*! \brief A saved set of adaptive equalizer coefficients for use after restarts. */
    /*complexi16_t*/ complexf_t  eq_coeff_save[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
    /*! \brief The equalizer signal buffer. */
    /*complexi16_t*/ complexf_t eq_buf[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
#else
    /*! \brief The scaling factor accessed by the AGC algorithm. */
    float agc_scaling;
    /*! \brief The previous value of agc_scaling, needed to reuse old training. */
    float agc_scaling_save;

    /*! \brief The current delta factor for updating the equalizer coefficients. */
    float eq_delta;
    /*! \brief The adaptive equalizer coefficients. */
    complexf_t eq_coeff[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
    /*! \brief A saved set of adaptive equalizer coefficients for use after restarts. */
    complexf_t eq_coeff_save[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
    /*! \brief The equalizer signal buffer. */
    complexf_t eq_buf[V27TER_EQUALIZER_PRE_LEN + 1 + V27TER_EQUALIZER_POST_LEN];
#endif

    /*! \brief Integration variable for damping the Gardner algorithm tests. */
    int gardner_integrate;
    /*! \brief Current step size of Gardner algorithm integration. */
    int gardner_step;
    /*! \brief The total symbol timing correction since the carrier came up.
               This is only for performance analysis purposes. */
    int total_baud_timing_correction;

    /*! \brief Starting phase angles for the coarse carrier aquisition step. */
    int32_t start_angles[2];
    /*! \brief History list of phase angles for the coarse carrier aquisition step. */
    int32_t angles[16];
    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
