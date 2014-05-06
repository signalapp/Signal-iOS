/*
 * SpanDSP - a series of DSP components for telephony
 *
 * async.h - Asynchronous serial bit stream encoding and decoding
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
 * $Id: async.h,v 1.25 2009/04/23 14:12:34 steveu Exp $
 */

/*! \file */

/*! \page async_page Asynchronous bit stream processing
\section async_page_sec_1 What does it do?
The asynchronous serial bit stream processing module provides
generation and decoding facilities for most asynchronous data
formats. It supports:
 - 1 or 2 stop bits.
 - Odd, even or no parity.
 - 5, 6, 7, or 8 bit characters.
 - V.14 rate adaption.
The input to this module is a bit stream. This means any symbol synchronisation
and decoding must occur before data is fed to this module.

\section async_page_sec_2 The transmitter
???.

\section async_page_sec_3 The receiver
???.
*/

#if !defined(_SPANDSP_ASYNC_H_)
#define _SPANDSP_ASYNC_H_

/*! Special "bit" values for the bitstream put and get functions, and the signal status functions. */
enum
{
    /*! \brief The carrier signal has dropped. */
    SIG_STATUS_CARRIER_DOWN = -1,
    /*! \brief The carrier signal is up. This merely indicates that carrier
         energy has been seen. It is not an indication that the carrier is either
         valid, or of the expected type. */
    SIG_STATUS_CARRIER_UP = -2,
    /*! \brief The modem is training. This is an early indication that the
        signal seems to be of the right type. This may be needed in time critical
        applications, like T.38, to forward an early indication of what is happening
        on the wire. */
    SIG_STATUS_TRAINING_IN_PROGRESS = -3,
    /*! \brief The modem has trained, and is ready for data exchange. */
    SIG_STATUS_TRAINING_SUCCEEDED = -4,
    /*! \brief The modem has failed to train. */
    SIG_STATUS_TRAINING_FAILED = -5,
    /*! \brief Packet framing (e.g. HDLC framing) is OK. */
    SIG_STATUS_FRAMING_OK = -6,
    /*! \brief The data stream has ended. */
    SIG_STATUS_END_OF_DATA = -7,
    /*! \brief An abort signal (e.g. an HDLC abort) has been received. */
    SIG_STATUS_ABORT = -8,
    /*! \brief A break signal (e.g. an async break) has been received. */
    SIG_STATUS_BREAK = -9,
    /*! \brief A modem has completed its task, and shut down. */
    SIG_STATUS_SHUTDOWN_COMPLETE = -10,
    /*! \brief Regular octet report for things like HDLC to the MTP standards. */
    SIG_STATUS_OCTET_REPORT = -11,
    /*! \brief Notification that a modem has detected signal quality degradation. */
    SIG_STATUS_POOR_SIGNAL_QUALITY = -12,
    /*! \brief Notification that a modem retrain has occurred. */
    SIG_STATUS_MODEM_RETRAIN_OCCURRED = -13
};

/*! Message put function for data pumps */
typedef void (*put_msg_func_t)(void *user_data, const uint8_t *msg, int len);

/*! Message get function for data pumps */
typedef int (*get_msg_func_t)(void *user_data, uint8_t *msg, int max_len);

/*! Byte put function for data pumps */
typedef void (*put_byte_func_t)(void *user_data, int byte);

/*! Byte get function for data pumps */
typedef int (*get_byte_func_t)(void *user_data);

/*! Bit put function for data pumps */
typedef void (*put_bit_func_t)(void *user_data, int bit);

/*! Bit get function for data pumps */
typedef int (*get_bit_func_t)(void *user_data);

/*! Completion callback function for tx data pumps */
typedef void (*modem_tx_status_func_t)(void *user_data, int status);

/*! Completion callback function for rx data pumps */
typedef void (*modem_rx_status_func_t)(void *user_data, int status);

enum
{
    /*! No parity bit should be used */
    ASYNC_PARITY_NONE = 0,
    /*! An even parity bit will exist, after the data bits */
    ASYNC_PARITY_EVEN,
    /*! An odd parity bit will exist, after the data bits */
    ASYNC_PARITY_ODD
};

/*!
    Asynchronous data transmit descriptor. This defines the state of a single
    working instance of a byte to asynchronous serial converter, for use
    in FSK modems.
*/
typedef struct async_tx_state_s async_tx_state_t;

/*!
    Asynchronous data receive descriptor. This defines the state of a single
    working instance of an asynchronous serial to byte converter, for use
    in FSK modems.
*/
typedef struct async_rx_state_s async_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Convert a signal status to a short text description.
    \brief Convert a signal status to a short text description.
    \param status The modem signal status.
    \return A pointer to the description. */
SPAN_DECLARE(const char *) signal_status_to_str(int status);

/*! Initialise an asynchronous data transmit context.
    \brief Initialise an asynchronous data transmit context.
    \param s The transmitter context.
    \param data_bits The number of data bit.
    \param parity_bits The type of parity.
    \param stop_bits The number of stop bits.
    \param use_v14 TRUE if V.14 rate adaption processing should be used.
    \param get_byte The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer.
    \return A pointer to the initialised context, or NULL if there was a problem. */
SPAN_DECLARE(async_tx_state_t *) async_tx_init(async_tx_state_t *s,
                                               int data_bits,
                                               int parity_bits,
                                               int stop_bits,
                                               int use_v14,
                                               get_byte_func_t get_byte,
                                               void *user_data);

SPAN_DECLARE(int) async_tx_release(async_tx_state_t *s);

SPAN_DECLARE(int) async_tx_free(async_tx_state_t *s);

/*! Get the next bit of a transmitted serial bit stream.
    \brief Get the next bit of a transmitted serial bit stream.
    \param user_data An opaque point which must point to a transmitter context.
    \return the next bit, or PUTBIT_END_OF_DATA to indicate the data stream has ended. */
SPAN_DECLARE_NONSTD(int) async_tx_get_bit(void *user_data);

/*! Initialise an asynchronous data receiver context.
    \brief Initialise an asynchronous data receiver context.
    \param s The receiver context.
    \param data_bits The number of data bits.
    \param parity_bits The type of parity.
    \param stop_bits The number of stop bits.
    \param use_v14 TRUE if V.14 rate adaption processing should be used.
    \param put_byte The callback routine used to put the received data.
    \param user_data An opaque pointer.
    \return A pointer to the initialised context, or NULL if there was a problem. */
SPAN_DECLARE(async_rx_state_t *) async_rx_init(async_rx_state_t *s,
                                               int data_bits,
                                               int parity_bits,
                                               int stop_bits,
                                               int use_v14,
                                               put_byte_func_t put_byte,
                                               void *user_data);

SPAN_DECLARE(int) async_rx_release(async_rx_state_t *s);

SPAN_DECLARE(int) async_rx_free(async_rx_state_t *s);

/*! Accept a bit from a received serial bit stream
    \brief Accept a bit from a received serial bit stream
    \param user_data An opaque point which must point to a receiver context.
    \param bit The new bit. Some special values are supported for this field.
        - SIG_STATUS_CARRIER_UP
        - SIG_STATUS_CARRIER_DOWN
        - SIG_STATUS_TRAINING_SUCCEEDED
        - SIG_STATUS_TRAINING_FAILED
        - SIG_STATUS_END_OF_DATA */
SPAN_DECLARE_NONSTD(void) async_rx_put_bit(void *user_data, int bit);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
