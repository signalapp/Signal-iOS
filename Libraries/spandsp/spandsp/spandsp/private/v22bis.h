/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/v22bis.h - ITU V.22bis modem
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004 Steve Underwood
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
 * $Id: v22bis.h,v 1.12 2009/11/04 15:52:06 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_V22BIS_H_)
#define _SPANDSP_PRIVATE_V22BIS_H_

/*! The number of steps to the left and to the right of the target position in the equalizer buffer. */
#define V22BIS_EQUALIZER_LEN    7
/*! One less than a power of 2 >= (2*V22BIS_EQUALIZER_LEN + 1) */
#define V22BIS_EQUALIZER_MASK   15

/*! The number of taps in the transmit pulse shaping filter */
#define V22BIS_TX_FILTER_STEPS  9

/*! The number of taps in the receive pulse shaping/bandpass filter */
#define V22BIS_RX_FILTER_STEPS  37

/*! Segments of the training sequence on the receive side */
enum
{
    V22BIS_RX_TRAINING_STAGE_NORMAL_OPERATION,
    V22BIS_RX_TRAINING_STAGE_SYMBOL_ACQUISITION,
    V22BIS_RX_TRAINING_STAGE_LOG_PHASE,
    V22BIS_RX_TRAINING_STAGE_UNSCRAMBLED_ONES,
    V22BIS_RX_TRAINING_STAGE_UNSCRAMBLED_ONES_SUSTAINING,
    V22BIS_RX_TRAINING_STAGE_SCRAMBLED_ONES_AT_1200,
    V22BIS_RX_TRAINING_STAGE_SCRAMBLED_ONES_AT_1200_SUSTAINING,
    V22BIS_RX_TRAINING_STAGE_WAIT_FOR_SCRAMBLED_ONES_AT_2400,
    V22BIS_RX_TRAINING_STAGE_PARKED
};

/*! Segments of the training sequence on the transmit side */
enum
{
    V22BIS_TX_TRAINING_STAGE_NORMAL_OPERATION = 0,
    V22BIS_TX_TRAINING_STAGE_INITIAL_TIMED_SILENCE,
    V22BIS_TX_TRAINING_STAGE_INITIAL_SILENCE,
    V22BIS_TX_TRAINING_STAGE_U11,
    V22BIS_TX_TRAINING_STAGE_U0011,
    V22BIS_TX_TRAINING_STAGE_S11,
    V22BIS_TX_TRAINING_STAGE_TIMED_S11,
    V22BIS_TX_TRAINING_STAGE_S1111,
    V22BIS_TX_TRAINING_STAGE_PARKED
};

/*!
    V.22bis modem descriptor. This defines the working state for a single instance
    of a V.22bis modem.
*/
struct v22bis_state_s
{
    /*! \brief The maximum permitted bit rate of the modem. Valid values are 1200 and 2400. */
    int bit_rate;
    /*! \brief TRUE is this is the calling side modem. */
    int calling_party;
    /*! \brief The callback function used to get the next bit to be transmitted. */
    get_bit_func_t get_bit;
    /*! \brief A user specified opaque pointer passed to the get_bit callback routine. */
    void *get_bit_user_data;
    /*! \brief The callback function used to put each bit received. */
    put_bit_func_t put_bit;
    /*! \brief A user specified opaque pointer passed to the put_bit callback routine. */
    void *put_bit_user_data;
    /*! \brief The callback function used to report modem status changes. */
    modem_rx_status_func_t status_handler;
    /*! \brief A user specified opaque pointer passed to the status function. */
    void *status_user_data;

    int negotiated_bit_rate;

    /* Receive section */
    struct
    {
        /*! \brief The route raised cosine (RRC) pulse shaping filter buffer. */
        float rrc_filter[2*V22BIS_RX_FILTER_STEPS];
        /*! \brief Current offset into the RRC pulse shaping filter buffer. */
        int rrc_filter_step;

        /*! \brief The register for the data scrambler. */
        unsigned int scramble_reg;
        /*! \brief A counter for the number of consecutive bits of repeating pattern through
                   the scrambler. */
        int scrambler_pattern_count;

        /*! \brief 0 if receiving user data. A training stage value during training */
        int training;
        /*! \brief A count of how far through the current training step we are. */
        int training_count;

        /*! \brief >0 if a signal above the minimum is present. It may or may not be a V.22bis signal. */
        int signal_present;

        /*! \brief A measure of how much mismatch there is between the real constellation,
            and the decoded symbol positions. */
        float training_error;

        /*! \brief The current phase of the carrier (i.e. the DDS parameter). */
        uint32_t carrier_phase;
        /*! \brief The update rate for the phase of the carrier (i.e. the DDS increment). */
        int32_t carrier_phase_rate;
        /*! \brief The proportional part of the carrier tracking filter. */
        float carrier_track_p;
        /*! \brief The integral part of the carrier tracking filter. */
        float carrier_track_i;
        
        /*! \brief A callback function which may be enabled to report every symbol's
                   constellation position. */
        qam_report_handler_t qam_report;
        /*! \brief A user specified opaque pointer passed to the qam_report callback
                   routine. */
        void *qam_user_data;

        /*! \brief A power meter, to measure the HPF'ed signal power in the channel. */    
        power_meter_t rx_power;
        /*! \brief The power meter level at which carrier on is declared. */
        int32_t carrier_on_power;
        /*! \brief The power meter level at which carrier off is declared. */
        int32_t carrier_off_power;
        /*! \brief The scaling factor accessed by the AGC algorithm. */
        float agc_scaling;
    
        int constellation_state;

        /*! \brief The current delta factor for updating the equalizer coefficients. */
        float eq_delta;
#if defined(SPANDSP_USE_FIXED_POINTx)
        /*! \brief The adaptive equalizer coefficients. */
        complexi_t eq_coeff[2*V22BIS_EQUALIZER_LEN + 1];
        /*! \brief The equalizer signal buffer. */
        complexi_t eq_buf[V22BIS_EQUALIZER_MASK + 1];
#else
        complexf_t eq_coeff[2*V22BIS_EQUALIZER_LEN + 1];
        complexf_t eq_buf[V22BIS_EQUALIZER_MASK + 1];
#endif
        /*! \brief Current offset into the equalizer buffer. */
        int eq_step;
        /*! \brief Current write offset into the equalizer buffer. */
        int eq_put_step;

        /*! \brief Integration variable for damping the Gardner algorithm tests. */
        int gardner_integrate;
        /*! \brief Current step size of Gardner algorithm integration. */
        int gardner_step;
        /*! \brief The total symbol timing correction since the carrier came up.
                   This is only for performance analysis purposes. */
        int total_baud_timing_correction;
        /*! \brief The current fractional phase of the baud timing. */
        int baud_phase;
    
        int sixteen_way_decisions;

        int pattern_repeats;
        int last_raw_bits;
    } rx;

    /* Transmit section */
    struct
    {
        /*! \brief The gain factor needed to achieve the specified output power. */
        float gain;

        /*! \brief The route raised cosine (RRC) pulse shaping filter buffer. */
        complexf_t rrc_filter[2*V22BIS_TX_FILTER_STEPS];
        /*! \brief Current offset into the RRC pulse shaping filter buffer. */
        int rrc_filter_step;

        /*! \brief The register for the data scrambler. */
        unsigned int scramble_reg;
        /*! \brief A counter for the number of consecutive bits of repeating pattern through
                   the scrambler. */
        int scrambler_pattern_count;

        /*! \brief 0 if transmitting user data. A training stage value during training */
        int training;
        /*! \brief A counter used to track progress through sending the training sequence. */
        int training_count;
        /*! \brief The current phase of the carrier (i.e. the DDS parameter). */
        uint32_t carrier_phase;
        /*! \brief The update rate for the phase of the carrier (i.e. the DDS increment). */
        int32_t carrier_phase_rate;
        /*! \brief The current phase of the guard tone (i.e. the DDS parameter). */
        uint32_t guard_phase;
        /*! \brief The update rate for the phase of the guard tone (i.e. the DDS increment). */
        int32_t guard_phase_rate;
        float guard_level;
        /*! \brief The current fractional phase of the baud timing. */
        int baud_phase;
        /*! \brief The code number for the current position in the constellation. */
        int constellation_state;
        /*! \brief An indicator to mark that we are tidying up to stop transmission. */
        int shutdown;
        /*! \brief The get_bit function in use at any instant. */
        get_bit_func_t current_get_bit;
    } tx;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Reinitialise an existing V.22bis modem receive context.
    \brief Reinitialise an existing V.22bis modem receive context.
    \param s The modem context.
    \return 0 for OK, -1 for bad parameter */
int v22bis_rx_restart(v22bis_state_t *s);

void v22bis_report_status_change(v22bis_state_t *s, int status);

void v22bis_equalizer_coefficient_reset(v22bis_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
