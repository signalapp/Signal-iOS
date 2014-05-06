/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/hdlc.h
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
 * $Id: hdlc.h,v 1.3 2009/02/12 12:38:39 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_HDLC_H_)
#define _SPANDSP_PRIVATE_HDLC_H_

/*!
    HDLC receive descriptor. This contains all the state information for an HDLC receiver.
 */
struct hdlc_rx_state_s
{
    /*! 2 for CRC-16, 4 for CRC-32 */
    int crc_bytes;
    /*! \brief Maximum permitted frame length. */
    size_t max_frame_len;
    /*! \brief The callback routine called to process each good received frame. */
    hdlc_frame_handler_t frame_handler;
    /*! \brief An opaque parameter passed to the frame callback routine. */
    void *frame_user_data;
    /*! \brief The callback routine called to report status changes. */
    modem_rx_status_func_t status_handler;
    /*! \brief An opaque parameter passed to the status callback routine. */
    void *status_user_data;
    /*! \brief TRUE if bad frames are to be reported. */
    int report_bad_frames;
    /*! \brief The number of consecutive flags which must be seen before framing is
        declared OK. */
    int framing_ok_threshold;
    /*! \brief TRUE if framing OK has been announced. */
    int framing_ok_announced;
    /*! \brief Number of consecutive flags seen so far. */
    int flags_seen;

    /*! \brief The raw (stuffed) bit stream buffer. */
    unsigned int raw_bit_stream;
    /*! \brief The destuffed bit stream buffer. */
    unsigned int byte_in_progress;
    /*! \brief The current number of bits in byte_in_progress. */
    int num_bits;
    /*! \brief TRUE if in octet counting mode (e.g. for MTP). */
    int octet_counting_mode;
    /*! \brief Octet count, to achieve the functionality needed for things
               like MTP. */
    int octet_count;
    /*! \brief The number of octets to be allowed between octet count reports. */
    int octet_count_report_interval;

    /*! \brief Buffer for a frame in progress. */
    uint8_t buffer[HDLC_MAXFRAME_LEN + 4];
    /*! \brief Length of a frame in progress. */
    size_t len;

    /*! \brief The number of bytes of good frames received (CRC not included). */
    unsigned long int rx_bytes;
    /*! \brief The number of good frames received. */
    unsigned long int rx_frames;
    /*! \brief The number of frames with CRC errors received. */
    unsigned long int rx_crc_errors;
    /*! \brief The number of too short and too long frames received. */
    unsigned long int rx_length_errors;
    /*! \brief The number of HDLC aborts received. */
    unsigned long int rx_aborts;
};

/*!
    HDLC transmit descriptor. This contains all the state information for an
    HDLC transmitter.
 */
struct hdlc_tx_state_s
{
    /*! 2 for CRC-16, 4 for CRC-32 */
    int crc_bytes;
    /*! \brief The callback routine called to indicate transmit underflow. */
    hdlc_underflow_handler_t underflow_handler;
    /*! \brief An opaque parameter passed to the callback routine. */
    void *user_data;
    /*! \brief The minimum flag octets to insert between frames. */
    int inter_frame_flags;
    /*! \brief TRUE if frame creation works in progressive mode. */
    int progressive;
    /*! \brief Maximum permitted frame length. */
    size_t max_frame_len;

    /*! \brief The stuffed bit stream being created. */
    uint32_t octets_in_progress;
    /*! \brief The number of bits currently in octets_in_progress. */
    int num_bits;
    /*! \brief The currently rotated state of the flag octet. */
    int idle_octet;
    /*! \brief The number of flag octets to send for a timed burst of flags. */
    int flag_octets;
    /*! \brief The number of abort octets to send for a timed burst of aborts. */
    int abort_octets;
    /*! \brief TRUE if the next underflow of timed flag octets should be reported */
    int report_flag_underflow;

    /*! \brief The current message being transmitted, with its CRC attached. */
    uint8_t buffer[HDLC_MAXFRAME_LEN + 4];
    /*! \brief The length of the message in the buffer. */
    size_t len;
    /*! \brief The current send position within the buffer. */
    size_t pos;
    /*! \brief The running CRC, as data fills the frame buffer. */
    uint32_t crc;

    /*! \brief The current byte being broken into bits for transmission. */
    int byte;
    /*! \brief The number of bits remaining in byte. */
    int bits;
    
    /*! \brief TRUE if transmission should end on buffer underflow .*/
    int tx_end;
};

#endif
/*- End of file ------------------------------------------------------------*/
