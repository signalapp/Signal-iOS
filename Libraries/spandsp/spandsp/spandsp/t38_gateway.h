/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t38_gateway.h - A T.38, less the packet exchange part
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005, 2006, 2007 Steve Underwood
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
 * $Id: t38_gateway.h,v 1.63 2009/04/12 09:12:10 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T38_GATEWAY_H_)
#define _SPANDSP_T38_GATEWAY_H_

/*! \page t38_gateway_page T.38 real time FAX over IP PSTN gateway
\section t38_gateway_page_sec_1 What does it do?

The T.38 gateway facility provides a robust interface between T.38 IP packet streams and
and 8k samples/second audio streams. It provides the buffering and flow control features needed
to maximum the tolerance of jitter and packet loss on the IP network.

\section t38_gateway_page_sec_2 How does it work?
*/

/*! The receive buffer length */
#define T38_RX_BUF_LEN          2048
/*! The number of HDLC transmit buffers */
#define T38_TX_HDLC_BUFS        256
/*! The maximum length of an HDLC frame buffer. This must be big enough for ECM frames. */
#define T38_MAX_HDLC_LEN        260

typedef struct t38_gateway_state_s t38_gateway_state_t;

/*!
    T.30 real time frame handler.
    \brief T.30 real time frame handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param direction TRUE for incoming, FALSE for outgoing.
    \param msg The HDLC message.
    \param len The length of the message.
*/
typedef void (t38_gateway_real_time_frame_handler_t)(t38_gateway_state_t *s,
                                                     void *user_data,
                                                     int direction,
                                                     const uint8_t *msg,
                                                     int len);

/*!
    T.38 gateway results.
 */
typedef struct
{
    /*! \brief The current bit rate for image transfer. */
    int bit_rate;
    /*! \brief TRUE if error correcting mode is used. */
    int error_correcting_mode;
    /*! \brief The number of pages transferred so far. */
    int pages_transferred;
} t38_stats_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Initialise a gateway mode T.38 context.
    \param s The T.38 context.
    \param tx_packet_handler A callback routine to encapsulate and transmit T.38 packets.
    \param tx_packet_user_data An opaque pointer passed to the tx_packet_handler routine.
    \return A pointer to the termination mode T.38 context, or NULL if there was a problem. */
SPAN_DECLARE(t38_gateway_state_t *) t38_gateway_init(t38_gateway_state_t *s,
                                                     t38_tx_packet_handler_t *tx_packet_handler,
                                                     void *tx_packet_user_data);

/*! Release a gateway mode T.38 context.
    \brief Release a T.38 context.
    \param s The T.38 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t38_gateway_release(t38_gateway_state_t *s);

/*! Free a gateway mode T.38 context.
    \brief Free a T.38 context.
    \param s The T.38 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t38_gateway_free(t38_gateway_state_t *s);

/*! Process a block of received FAX audio samples.
    \brief Process a block of received FAX audio samples.
    \param s The T.38 context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed. */
SPAN_DECLARE(int) t38_gateway_rx(t38_gateway_state_t *s, int16_t amp[], int len);

/*! Generate a block of FAX audio samples.
    \brief Generate a block of FAX audio samples.
    \param s The T.38 context.
    \param amp The audio sample buffer.
    \param max_len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE(int) t38_gateway_tx(t38_gateway_state_t *s, int16_t amp[], int max_len);

/*! Control whether error correcting mode (ECM) is allowed.
    \brief Control whether error correcting mode (ECM) is allowed.
    \param s The T.38 context.
    \param ecm_allowed TRUE is ECM is to be allowed.
*/
SPAN_DECLARE(void) t38_gateway_set_ecm_capability(t38_gateway_state_t *s, int ecm_allowed);

/*! Select whether silent audio will be sent when transmit is idle.
    \brief Select whether silent audio will be sent when transmit is idle.
    \param s The T.38 context.
    \param transmit_on_idle TRUE if silent audio should be output when the FAX transmitter is
           idle. FALSE to transmit zero length audio when the FAX transmitter is idle. The default
           behaviour is FALSE.
*/
SPAN_DECLARE(void) t38_gateway_set_transmit_on_idle(t38_gateway_state_t *s, int transmit_on_idle);

/*! Specify which modem types are supported by a T.30 context.
    \brief Specify supported modems.
    \param s The T.38 context.
    \param supported_modems Bit field list of the supported modems.
*/
SPAN_DECLARE(void) t38_gateway_set_supported_modems(t38_gateway_state_t *s, int supported_modems);

/*! Select whether NSC, NSF, and NSS should be suppressed. It selected, the contents of
    these messages are forced to zero for all octets beyond the message type. This makes
    them look like manufacturer specific messages, from a manufacturer which does not exist.
    \brief Select whether NSC, NSF, and NSS should be suppressed.
    \param s The T.38 context.
    \param from_t38 A string of bytes to overwrite the header of any NSC, NSF, and NSS
           frames passing through the gateway from T.38 the the modem.
    \param from_t38_len The length of the overwrite string.
    \param from_modem A string of bytes to overwrite the header of any NSC, NSF, and NSS
           frames passing through the gateway from the modem to T.38.
    \param from_modem_len The length of the overwrite string.
*/
SPAN_DECLARE(void) t38_gateway_set_nsx_suppression(t38_gateway_state_t *s,
                                                   const uint8_t *from_t38,
                                                   int from_t38_len,
                                                   const uint8_t *from_modem,
                                                   int from_modem_len);

/*! Select whether talker echo protection tone will be sent for the image modems.
    \brief Select whether TEP will be sent for the image modems.
    \param s The T.38 context.
    \param use_tep TRUE if TEP should be sent.
*/
SPAN_DECLARE(void) t38_gateway_set_tep_mode(t38_gateway_state_t *s, int use_tep);

/*! Select whether non-ECM fill bits are to be removed during transmission.
    \brief Select whether non-ECM fill bits are to be removed during transmission.
    \param s The T.38 context.
    \param remove TRUE if fill bits are to be removed.
*/
SPAN_DECLARE(void) t38_gateway_set_fill_bit_removal(t38_gateway_state_t *s, int remove);

/*! Get the current transfer statistics for the current T.38 session.
    \brief Get the current transfer statistics.
    \param s The T.38 context.
    \param t A pointer to a buffer for the statistics. */
SPAN_DECLARE(void) t38_gateway_get_transfer_statistics(t38_gateway_state_t *s, t38_stats_t *t);

/*! Get a pointer to the T.38 core IFP packet engine associated with a
    gateway mode T.38 context.
    \brief Get a pointer to the T.38 core IFP packet engine associated
           with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the T.38 core context, or NULL.
*/
SPAN_DECLARE(t38_core_state_t *) t38_gateway_get_t38_core_state(t38_gateway_state_t *s);

/*! Get a pointer to the logging context associated with a T.38 context.
    \brief Get a pointer to the logging context associated with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the logging context, or NULL.
*/
SPAN_DECLARE(logging_state_t *) t38_gateway_get_logging_state(t38_gateway_state_t *s);

/*! Set a callback function for T.30 frame exchange monitoring. This is called from the heart
    of the signal processing, so don't take too long in the handler routine.
    \brief Set a callback function for T.30 frame exchange monitoring.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t38_gateway_set_real_time_frame_handler(t38_gateway_state_t *s,
                                                           t38_gateway_real_time_frame_handler_t *handler,
                                                           void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
