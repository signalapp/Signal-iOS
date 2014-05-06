/*
 * SpanDSP - a series of DSP components for telephony
 *
 * hdlc.h
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
 * $Id: hdlc.h,v 1.45 2009/06/02 16:03:56 steveu Exp $
 */

/*! \file */

/*! \page hdlc_page HDLC

\section hdlc_page_sec_1 What does it do?
The HDLC module provides bit stuffing, destuffing, framing and deframing,
according to the HDLC protocol. It also provides 16 and 32 bit CRC generation
and checking services for HDLC frames.

HDLC may not be a DSP function, but is needed to accompany several DSP components.

\section hdlc_page_sec_2 How does it work?
*/

#if !defined(_SPANDSP_HDLC_H_)
#define _SPANDSP_HDLC_H_

/*! 
    HDLC_MAXFRAME_LEN is the maximum length of a stuffed HDLC frame, excluding the CRC.
*/
#define HDLC_MAXFRAME_LEN       400	

typedef void (*hdlc_frame_handler_t)(void *user_data, const uint8_t *pkt, int len, int ok);
typedef void (*hdlc_underflow_handler_t)(void *user_data);

/*!
    HDLC receive descriptor. This contains all the state information for an HDLC receiver.
 */
typedef struct hdlc_rx_state_s hdlc_rx_state_t;

/*!
    HDLC received data statistics.
 */
typedef struct
{
    /*! \brief The number of bytes of good frames received (CRC not included). */
    unsigned long int bytes;
    /*! \brief The number of good frames received. */
    unsigned long int good_frames;
    /*! \brief The number of frames with CRC errors received. */
    unsigned long int crc_errors;
    /*! \brief The number of too short and too long frames received. */
    unsigned long int length_errors;
    /*! \brief The number of HDLC aborts received. */
    unsigned long int aborts;
} hdlc_rx_stats_t;

/*!
    HDLC transmit descriptor. This contains all the state information for an
    HDLC transmitter.
 */
typedef struct hdlc_tx_state_s hdlc_tx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Initialise an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \param crc32 TRUE to use ITU CRC32. FALSE to use ITU CRC16.
    \param report_bad_frames TRUE to request the reporting of bad frames.
    \param framing_ok_threshold The number of back-to-back flags needed to
           start the framing OK condition. This may be used where a series of
           flag octets is used as a preamble, such as in the T.30 protocol.
    \param handler The function to be called when a good HDLC frame is received.
    \param user_data An opaque parameter for the callback routine.
    \return A pointer to the HDLC receiver context.
*/
SPAN_DECLARE(hdlc_rx_state_t *) hdlc_rx_init(hdlc_rx_state_t *s,
                                             int crc32,
                                             int report_bad_frames,
                                             int framing_ok_threshold,
                                             hdlc_frame_handler_t handler,
                                             void *user_data);

/*! Change the put_bit function associated with an HDLC receiver context.
    \brief Change the put_bit function associated with an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \param handler The function to be called when a good HDLC frame is received.
    \param user_data An opaque parameter for the callback routine.
*/
SPAN_DECLARE(void) hdlc_rx_set_frame_handler(hdlc_rx_state_t *s, hdlc_frame_handler_t handler, void *user_data);

/*! Change the status report function associated with an HDLC receiver context.
    \brief Change the status report function associated with an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \param handler The callback routine used to report status changes.
    \param user_data An opaque parameter for the callback routine.
*/
SPAN_DECLARE(void) hdlc_rx_set_status_handler(hdlc_rx_state_t *s, modem_rx_status_func_t handler, void *user_data);

/*! Release an HDLC receiver context.
    \brief Release an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \return 0 for OK */
SPAN_DECLARE(int) hdlc_rx_release(hdlc_rx_state_t *s);

/*! Free an HDLC receiver context.
    \brief Free an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \return 0 for OK */
SPAN_DECLARE(int) hdlc_rx_free(hdlc_rx_state_t *s);

/*! \brief Set the maximum frame length for an HDLC receiver context.
    \param s A pointer to an HDLC receiver context.
    \param max_len The maximum permitted length of a frame.
*/
SPAN_DECLARE(void) hdlc_rx_set_max_frame_len(hdlc_rx_state_t *s, size_t max_len);

/*! \brief Set the octet counting report interval.
    \param s A pointer to an HDLC receiver context.
    \param interval The interval, in octets.
*/
SPAN_DECLARE(void) hdlc_rx_set_octet_counting_report_interval(hdlc_rx_state_t *s,
                                                              int interval);

/*! \brief Get the current receive statistics.
    \param s A pointer to an HDLC receiver context.
    \param t A pointer to the buffer for the statistics.
    \return 0 for OK, else -1.
*/
SPAN_DECLARE(int) hdlc_rx_get_stats(hdlc_rx_state_t *s,
                                    hdlc_rx_stats_t *t);

/*! \brief Put a single bit of data to an HDLC receiver.
    \param s A pointer to an HDLC receiver context.
    \param new_bit The bit.
*/
SPAN_DECLARE_NONSTD(void) hdlc_rx_put_bit(hdlc_rx_state_t *s, int new_bit);

/*! \brief Put a byte of data to an HDLC receiver.
    \param s A pointer to an HDLC receiver context.
    \param new_byte The byte of data.
*/
SPAN_DECLARE_NONSTD(void) hdlc_rx_put_byte(hdlc_rx_state_t *s, int new_byte);

/*! \brief Put a series of bytes of data to an HDLC receiver.
    \param s A pointer to an HDLC receiver context.
    \param buf The buffer of data.
    \param len The length of the data in the buffer.
*/
SPAN_DECLARE_NONSTD(void) hdlc_rx_put(hdlc_rx_state_t *s, const uint8_t buf[], int len);

/*! \brief Initialise an HDLC transmitter context.
    \param s A pointer to an HDLC transmitter context.
    \param crc32 TRUE to use ITU CRC32. FALSE to use ITU CRC16.
    \param inter_frame_flags The minimum flag octets to insert between frames (usually one).
    \param progressive TRUE if frame creation works in progressive mode.
    \param handler The callback function called when the HDLC transmitter underflows.
    \param user_data An opaque parameter for the callback routine.
    \return A pointer to the HDLC transmitter context.
*/
SPAN_DECLARE(hdlc_tx_state_t *) hdlc_tx_init(hdlc_tx_state_t *s,
                                             int crc32,
                                             int inter_frame_flags,
                                             int progressive,
                                             hdlc_underflow_handler_t handler,
                                             void *user_data);

SPAN_DECLARE(int) hdlc_tx_release(hdlc_tx_state_t *s);

SPAN_DECLARE(int) hdlc_tx_free(hdlc_tx_state_t *s);

/*! \brief Set the maximum frame length for an HDLC transmitter context.
    \param s A pointer to an HDLC transmitter context.
    \param max_len The maximum length.
*/
SPAN_DECLARE(void) hdlc_tx_set_max_frame_len(hdlc_tx_state_t *s, size_t max_len);

/*! \brief Transmit a frame.
    \param s A pointer to an HDLC transmitter context.
    \param frame A pointer to the frame to be transmitted.
    \param len The length of the frame to be transmitted.
    \return 0 if the frame was accepted for transmission, else -1.
*/
SPAN_DECLARE(int) hdlc_tx_frame(hdlc_tx_state_t *s, const uint8_t *frame, size_t len);

/*! \brief Corrupt the frame currently being transmitted, by giving it the wrong CRC.
    \param s A pointer to an HDLC transmitter context.
    \return 0 if the frame was corrupted, else -1.
*/
SPAN_DECLARE(int) hdlc_tx_corrupt_frame(hdlc_tx_state_t *s);

/*! \brief Transmit a specified quantity of flag octets, typically as a preamble.
    \param s A pointer to an HDLC transmitter context.
    \param len The length of the required period of flags, in flag octets. If len is zero this
           requests that HDLC transmission be terminated when the buffers have fully
           drained.
    \return 0 if the flags were accepted for transmission, else -1.
*/
SPAN_DECLARE(int) hdlc_tx_flags(hdlc_tx_state_t *s, int len);

/*! \brief Send an abort.
    \param s A pointer to an HDLC transmitter context.
    \return 0 if the frame was aborted, else -1.
*/
SPAN_DECLARE(int) hdlc_tx_abort(hdlc_tx_state_t *s);

/*! \brief Get the next bit for transmission.
    \param s A pointer to an HDLC transmitter context.
    \return The next bit for transmission.
*/
SPAN_DECLARE_NONSTD(int) hdlc_tx_get_bit(hdlc_tx_state_t *s);

/*! \brief Get the next byte for transmission.
    \param s A pointer to an HDLC transmitter context.
    \return The next byte for transmission.
*/
SPAN_DECLARE_NONSTD(int) hdlc_tx_get_byte(hdlc_tx_state_t *s);

/*! \brief Get the next sequence of bytes for transmission.
    \param s A pointer to an HDLC transmitter context.
    \param buf The buffer for the data.
    \param max_len The number of bytes to get.
    \return The number of bytes actually got.
*/
SPAN_DECLARE_NONSTD(int) hdlc_tx_get(hdlc_tx_state_t *s, uint8_t buf[], size_t max_len);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
