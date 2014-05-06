/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/t30.h - definitions for T.30 fax processing
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
 * $Id: t30.h,v 1.5.4.1 2009/12/19 09:47:56 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_PRIVATE_T30_H_)
#define _SPANDSP_PRIVATE_T30_H_

/*!
    T.30 FAX channel descriptor. This defines the state of a single working
    instance of a T.30 FAX channel.
*/
struct t30_state_s
{
    /* This must be kept the first thing in the structure, so it can be pointed
       to reliably as the structures change over time. */
    /*! \brief T.4 context for reading or writing image data. */
    t4_state_t t4;
    
    /*! \brief The type of FAX operation currently in progress */
    int operation_in_progress;

    /*! \brief TRUE if behaving as the calling party */
    int calling_party;
    
    /*! \brief The received DCS, formatted as an ASCII string, for inclusion
               in the TIFF file. */
    char rx_dcs_string[T30_MAX_DIS_DTC_DCS_LEN*3 + 1];
    /*! \brief The text which will be used in FAX page header. No text results
               in no header line. */
    char header_info[T30_MAX_PAGE_HEADER_INFO + 1];
    /*! \brief The information fields received. */
    t30_exchanged_info_t rx_info;
    /*! \brief The information fields to be transmitted. */
    t30_exchanged_info_t tx_info;
    /*! \brief The country of origin of the remote machine, if known, else NULL. */
    const char *country;
    /*! \brief The vendor of the remote machine, if known, else NULL. */
    const char *vendor;
    /*! \brief The model of the remote machine, if known, else NULL. */
    const char *model;

    /*! \brief A pointer to a callback routine to be called when phase B events
        occur. */
    t30_phase_b_handler_t *phase_b_handler;
    /*! \brief An opaque pointer supplied in event B callbacks. */
    void *phase_b_user_data;
    /*! \brief A pointer to a callback routine to be called when phase D events
        occur. */
    t30_phase_d_handler_t *phase_d_handler;
    /*! \brief An opaque pointer supplied in event D callbacks. */
    void *phase_d_user_data;
    /*! \brief A pointer to a callback routine to be called when phase E events
        occur. */
    t30_phase_e_handler_t *phase_e_handler;
    /*! \brief An opaque pointer supplied in event E callbacks. */
    void *phase_e_user_data;
    /*! \brief A pointer to a callback routine to be called when frames are
        exchanged. */
    t30_real_time_frame_handler_t *real_time_frame_handler;
    /*! \brief An opaque pointer supplied in real time frame callbacks. */
    void *real_time_frame_user_data;

    /*! \brief A pointer to a callback routine to be called when document events
        (e.g. end of transmitted document) occur. */
    t30_document_handler_t *document_handler;
    /*! \brief An opaque pointer supplied in document callbacks. */
    void *document_user_data;

    /*! \brief The handler for changes to the receive mode */
    t30_set_handler_t *set_rx_type_handler;
    /*! \brief An opaque pointer passed to the handler for changes to the receive mode */
    void *set_rx_type_user_data;
    /*! \brief The handler for changes to the transmit mode */
    t30_set_handler_t *set_tx_type_handler;
    /*! \brief An opaque pointer passed to the handler for changes to the transmit mode */
    void *set_tx_type_user_data;

    /*! \brief The transmitted HDLC frame handler. */
    t30_send_hdlc_handler_t *send_hdlc_handler;
    /*! \brief An opaque pointer passed to the transmitted HDLC frame handler. */
    void *send_hdlc_user_data;

    /*! \brief The DIS code for the minimum scan row time we require. This is usually 0ms,
        but if we are trying to simulate another type of FAX machine, we may need a non-zero
        value here. */
    uint8_t local_min_scan_time_code;

    /*! \brief The current T.30 phase. */
    int phase;
    /*! \brief The T.30 phase to change to when the current phase ends. */
    int next_phase;
    /*! \brief The current state of the T.30 state machine. */
    int state;
    /*! \brief The step in sending a sequence of HDLC frames. */
    int step;

    /*! \brief The preparation buffer for the DCS message to be transmitted. */
    uint8_t dcs_frame[T30_MAX_DIS_DTC_DCS_LEN];
    /*! \brief The length of the DCS message to be transmitted. */
    int dcs_len;
    /*! \brief The preparation buffer for DIS or DTC message to be transmitted. */
    uint8_t local_dis_dtc_frame[T30_MAX_DIS_DTC_DCS_LEN];
    /*! \brief The length of the DIS or DTC message to be transmitted. */
    int local_dis_dtc_len;
    /*! \brief The last DIS or DTC message received form the far end. */
    uint8_t far_dis_dtc_frame[T30_MAX_DIS_DTC_DCS_LEN];
    /*! \brief The length of the last DIS or DTC message received form the far end. */
    int far_dis_dtc_len;
    /*! \brief TRUE if a valid DIS has been received from the far end. */
    int dis_received;

    /*! \brief A flag to indicate a message is in progress. */
    int in_message;

    /*! \brief TRUE if the short training sequence should be used. */
    int short_train;

    /*! \brief A count of the number of bits in the trainability test. This counts down to zero when
        sending TCF, and counts up when receiving it. */
    int tcf_test_bits;
    /*! \brief The current count of consecutive received zero bits, during the trainability test. */
    int tcf_current_zeros;
    /*! \brief The maximum consecutive received zero bits seen to date, during the trainability test. */
    int tcf_most_zeros;

    /*! \brief The current fallback step for the fast message transfer modem. */
    int current_fallback;
    /*! \brief The subset of supported modems allowed at the current time, allowing for negotiation. */
    int current_permitted_modems;
    /*! \brief TRUE if a carrier is present. Otherwise FALSE. */
    int rx_signal_present;
    /*! \brief TRUE if a modem has trained correctly. */
    int rx_trained;
    /*! \brief TRUE if a valid HDLC frame has been received in the current reception period. */
    int rx_frame_received;

    /*! \brief Current reception mode. */
    int current_rx_type;
    /*! \brief Current transmission mode. */
    int current_tx_type;

    /*! \brief T0 is the answer timeout when calling another FAX machine.
        Placing calls is handled outside the FAX processing, but this timeout keeps
        running until V.21 modulation is sent or received.
        T1 is the remote terminal identification timeout (in audio samples). */
    int timer_t0_t1;
    /*! \brief T2, T2A and T2B are the HDLC command timeouts.
               T4, T4A and T4B are the HDLC response timeouts (in audio samples). */
    int timer_t2_t4;
    /*! \brief A value specifying which of the possible timers is currently running in timer_t2_t4 */
    int timer_t2_t4_is;
    /*! \brief Procedural interrupt timeout (in audio samples). */
    int timer_t3;
    /*! \brief This is only used in error correcting mode. */
    int timer_t5;
    /*! \brief This is only used in full duplex (e.g. ISDN) modes. */
    int timer_t6;
    /*! \brief This is only used in full duplex (e.g. ISDN) modes. */
    int timer_t7;
    /*! \brief This is only used in full duplex (e.g. ISDN) modes. */
    int timer_t8;

    /*! \brief TRUE once the far end FAX entity has been detected. */
    int far_end_detected;

    /*! \brief TRUE if a local T.30 interrupt is pending. */
    int local_interrupt_pending;
    /*! \brief The image coding being used on the line. */
    int line_encoding;
    /*! \brief The image coding being used for output files. */
    int output_encoding;
    /*! \brief The current DCS message minimum scan time code. */
    uint8_t min_scan_time_code;
    /*! \brief The X direction resolution of the current image, in pixels per metre. */
    int x_resolution;
    /*! \brief The Y direction resolution of the current image, in pixels per metre. */
    int y_resolution;
    /*! \brief The width of the current image, in pixels. */
    t4_image_width_t image_width;
    /*! \brief Current number of retries of the action in progress. */
    int retries;
    /*! \brief TRUE if error correcting mode is used. */
    int error_correcting_mode;
    /*! \brief The number of HDLC frame retries, if error correcting mode is used. */
    int error_correcting_mode_retries;
    /*! \brief The current count of consecutive T30_PPR messages. */
    int ppr_count;
    /*! \brief The current count of consecutive T30_RNR messages. */
    int receiver_not_ready_count;
    /*! \brief The number of octets to be used per ECM frame. */
    int octets_per_ecm_frame;
    /*! \brief The ECM partial page buffer. */
    uint8_t ecm_data[256][260];
    /*! \brief The lengths of the frames in the ECM partial page buffer. */
    int16_t ecm_len[256];
    /*! \brief A bit map of the OK ECM frames, constructed as a PPR frame. */
    uint8_t ecm_frame_map[3 + 32];
    
    /*! \brief The current page number for receiving, in ECM or non-ECM mode. This is reset at the start of a call. */
    int rx_page_number;
    /*! \brief The current page number for sending, in ECM or non-ECM mode. This is reset at the start of a call. */
    int tx_page_number;
    /*! \brief The current block number, in ECM mode */
    int ecm_block;
    /*! \brief The number of frames in the current block number, in ECM mode */
    int ecm_frames;
    /*! \brief The number of frames sent in the current burst of image transmission, in ECM mode */
    int ecm_frames_this_tx_burst;
    /*! \brief The current ECM frame, during ECM transmission. */
    int ecm_current_tx_frame;
    /*! \brief TRUE if we are at the end of an ECM page to se sent - i.e. there are no more
        partial pages still to come. */
    int ecm_at_page_end;

    /*! \brief The transmission step queued to follow the one in progress. */
    int next_tx_step;
    /*! \brief The FCF for the next receive step. */
    uint8_t next_rx_step;
    /*! \brief Image file name for image reception. */
    char rx_file[256];
    /*! \brief The last page we are prepared accept for a received image file. -1 means no restriction. */
    int rx_stop_page;
    /*! \brief Image file name to be sent. */
    char tx_file[256];
    /*! \brief The first page to be sent from the image file. -1 means no restriction. */
    int tx_start_page;
    /*! \brief The last page to be sent from the image file. -1 means no restriction. */
    int tx_stop_page;
    /*! \brief The current completion status. */
    int current_status;
    /*! \brief Internet aware FAX mode bit mask. */
    int iaf;
    /*! \brief A bit mask of the currently supported modem types. */
    int supported_modems;
    /*! \brief A bit mask of the currently supported image compression modes. */
    int supported_compressions;
    /*! \brief A bit mask of the currently supported image resolutions. */
    int supported_resolutions;
    /*! \brief A bit mask of the currently supported image sizes. */
    int supported_image_sizes;
    /*! \brief A bit mask of the currently supported T.30 special features. */
    int supported_t30_features;
    /*! \brief TRUE is ECM mode handling is enabled. */
    int ecm_allowed;
    
    /*! \brief the FCF2 field of the last PPS message we received. */
    uint8_t last_pps_fcf2;
    /*! \brief The number of the first ECM frame which we do not currently received correctly. For
        a partial page received correctly, this will be one greater than the number of frames it
        contains. */
    int ecm_first_bad_frame;
    /*! \brief A count of successfully received ECM frames, to assess progress as a basis for
        deciding whether to continue error correction when PPRs keep repeating. */
    int ecm_progress;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
