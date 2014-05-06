/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t38_core.h - An implementation of T.38, less the packet exchange part
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
 * $Id: t38_core.h,v 1.39 2009/07/14 13:54:22 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T38_CORE_H_)
#define _SPANDSP_T38_CORE_H_

/*! \page t38_core_page T.38 real time FAX over IP message handling
There are two ITU recommendations which address sending FAXes over IP networks. T.37 specifies a
method of encapsulating FAX images in e-mails, and transporting them to the recipient (an e-mail
box, or another FAX machine) in a store-and-forward manner. T.38 defines a protocol for
transmitting a FAX across an IP network in real time. The core T.38 modules implements the basic
message handling for the T.38, real time, FAX over IP (FoIP) protocol.

The T.38 protocol can operate between:
    - Internet-aware FAX terminals, which connect directly to an IP network. The T.38 terminal module
      extends this module to provide a complete T.38 terminal.
    - FAX gateways, which allow traditional PSTN FAX terminals to communicate through the Internet.
      The T.38 gateway module extends this module to provide a T.38 gateway.
    - A combination of terminals and gateways.

T.38 is the only standardised protocol which exists for real-time FoIP. Reliably transporting a
FAX between PSTN FAX terminals, through an IP network, requires use of the T.38 protocol at FAX
gateways. VoIP connections are not robust for modem use, including FAX modem use. Most use low
bit rate codecs, which cannot convey the modem signals accurately. Even when high bit rate
codecs are used, VoIP connections suffer dropouts and timing adjustments, which modems cannot
tolerate. In a LAN environment the dropout rate may be very low, but the timing adjustments which
occur in VoIP connections still make modem operation unreliable. T.38 FAX gateways deal with the
delays, timing jitter, and packet loss experienced in packet networks, and isolate the PSTN FAX
terminals from these as far as possible. In addition, by sending FAXes as image data, rather than
digitised audio, they reduce the required bandwidth of the IP network.

\section t38_core_page_sec_1 What does it do?

\section t38_core_page_sec_2 How does it work?

Timing differences and jitter between two T.38 entities can be a serious problem, if one of those
entities is a PSTN gateway.

Flow control for non-ECM image data takes advantage of several features of the T.30 specification.
First, an unspecified number of 0xFF octets may be sent at the start of transmission. This means we
can add endless extra 0xFF bytes at this point, without breaking the T.30 spec. In practice, we
cannot add too many, or we will affect the timing tolerance of the T.30 protocol by delaying the
response at the end of each image. Secondly, just before an end of line (EOL) marker we can pad
with zero bits. Again, the number is limited only by need to avoid upsetting the timing of the
step following the non-ECM data.
*/

/*! T.38 indicator types */
enum t30_indicator_types_e
{
    T38_IND_NO_SIGNAL = 0,
    T38_IND_CNG,
    T38_IND_CED,
    T38_IND_V21_PREAMBLE,
    T38_IND_V27TER_2400_TRAINING,
    T38_IND_V27TER_4800_TRAINING,
    T38_IND_V29_7200_TRAINING,
    T38_IND_V29_9600_TRAINING,
    T38_IND_V17_7200_SHORT_TRAINING,
    T38_IND_V17_7200_LONG_TRAINING,
    T38_IND_V17_9600_SHORT_TRAINING,
    T38_IND_V17_9600_LONG_TRAINING,
    T38_IND_V17_12000_SHORT_TRAINING,
    T38_IND_V17_12000_LONG_TRAINING,
    T38_IND_V17_14400_SHORT_TRAINING,
    T38_IND_V17_14400_LONG_TRAINING,
    T38_IND_V8_ANSAM,
    T38_IND_V8_SIGNAL,
    T38_IND_V34_CNTL_CHANNEL_1200,
    T38_IND_V34_PRI_CHANNEL,
    T38_IND_V34_CC_RETRAIN,
    T38_IND_V33_12000_TRAINING,
    T38_IND_V33_14400_TRAINING
};

/*! T.38 data types */
enum t38_data_types_e
{
    T38_DATA_NONE = -1,
    T38_DATA_V21 = 0,
    T38_DATA_V27TER_2400,
    T38_DATA_V27TER_4800,
    T38_DATA_V29_7200,
    T38_DATA_V29_9600,
    T38_DATA_V17_7200,
    T38_DATA_V17_9600,
    T38_DATA_V17_12000,
    T38_DATA_V17_14400,
    T38_DATA_V8,
    T38_DATA_V34_PRI_RATE,
    T38_DATA_V34_CC_1200,
    T38_DATA_V34_PRI_CH,
    T38_DATA_V33_12000,
    T38_DATA_V33_14400
};

/*! T.38 data field types */
enum t38_field_types_e
{
    T38_FIELD_HDLC_DATA = 0,
    T38_FIELD_HDLC_SIG_END,
    T38_FIELD_HDLC_FCS_OK,
    T38_FIELD_HDLC_FCS_BAD,
    T38_FIELD_HDLC_FCS_OK_SIG_END,
    T38_FIELD_HDLC_FCS_BAD_SIG_END,
    T38_FIELD_T4_NON_ECM_DATA,
    T38_FIELD_T4_NON_ECM_SIG_END,
    T38_FIELD_CM_MESSAGE,
    T38_FIELD_JM_MESSAGE,
    T38_FIELD_CI_MESSAGE,
    T38_FIELD_V34RATE
};

/*! T.38 field classes */
enum t38_field_classes_e
{
    T38_FIELD_CLASS_NONE = 0,
    T38_FIELD_CLASS_HDLC,
    T38_FIELD_CLASS_NON_ECM
};

/*! T.38 message types */
enum t38_message_types_e
{
    T38_TYPE_OF_MSG_T30_INDICATOR = 0,
    T38_TYPE_OF_MSG_T30_DATA
};

/*! T.38 transport types */
enum t38_transport_types_e
{
    T38_TRANSPORT_UDPTL = 0,
    T38_TRANSPORT_RTP,
    T38_TRANSPORT_TCP
};

/*! T.38 TCF management types */
enum t38_data_rate_management_types_e
{
    T38_DATA_RATE_MANAGEMENT_LOCAL_TCF = 1,
    T38_DATA_RATE_MANAGEMENT_TRANSFERRED_TCF = 2
};

/*! T.38 Packet categories used for setting the redundancy level and packet repeat
    counts on a packet by packet basis. */
enum t38_packet_categories_e
{
    /*! \brief Indicator packet */
    T38_PACKET_CATEGORY_INDICATOR = 0,
    /*! \brief Control data packet */
    T38_PACKET_CATEGORY_CONTROL_DATA = 1,
    /*! \brief Terminating control data packet */
    T38_PACKET_CATEGORY_CONTROL_DATA_END = 2,
    /*! \brief Image data packet */
    T38_PACKET_CATEGORY_IMAGE_DATA = 3,
    /*! \brief Terminating image data packet */
    T38_PACKET_CATEGORY_IMAGE_DATA_END = 4
};

#define T38_RX_BUF_LEN  2048
#define T38_TX_BUF_LEN  16384

/*! T.38 data field */
typedef struct
{
    /*! Field type */
    int field_type;
    /*! Field contents */
    const uint8_t *field;
    /*! Field length */
    int field_len;
} t38_data_field_t;

/*!
    Core T.38 state, common to all modes of T.38.
*/
typedef struct t38_core_state_s t38_core_state_t;

typedef int (t38_tx_packet_handler_t)(t38_core_state_t *s, void *user_data, const uint8_t *buf, int len, int count);

typedef int (t38_rx_indicator_handler_t)(t38_core_state_t *s, void *user_data, int indicator);
typedef int (t38_rx_data_handler_t)(t38_core_state_t *s, void *user_data, int data_type, int field_type, const uint8_t *buf, int len);
typedef int (t38_rx_missing_handler_t)(t38_core_state_t *s, void *user_data, int rx_seq_no, int expected_seq_no);

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Convert the code for an indicator to a short text name.
    \param indicator The type of indicator.
    \return A pointer to a short text name for the indicator. */
SPAN_DECLARE(const char *) t38_indicator_to_str(int indicator);

/*! \brief Convert the code for a type of data to a short text name.
    \param data_type The data type.
    \return A pointer to a short text name for the data type. */
SPAN_DECLARE(const char *) t38_data_type_to_str(int data_type);

/*! \brief Convert the code for a type of data field to a short text name.
    \param field_type The field type.
    \return A pointer to a short text name for the field type. */
SPAN_DECLARE(const char *) t38_field_type_to_str(int field_type);

/*! \brief Convert the code for a CM profile code to text description.
    \param profile The profile code from a CM message.
    \return A pointer to a short text description of the profile. */
SPAN_DECLARE(const char *) t38_cm_profile_to_str(int profile);

/*! \brief Convert a JM message code to text description.
    \param data The data field of the message.
    \param len The length of the data field.
    \return A pointer to a short text description of the profile. */
SPAN_DECLARE(const char *) t38_jm_to_str(const uint8_t *data, int len);

/*! \brief Convert a V34rate message to an actual bit rate.
    \param data The data field of the message.
    \param len The length of the data field.
    \return The bit rate, or -1 for a bad message. */
SPAN_DECLARE(int) t38_v34rate_to_bps(const uint8_t *data, int len);

/*! \brief Send an indicator packet
    \param s The T.38 context.
    \param indicator The indicator to send.
    \return The delay to allow after this indicator is sent. */
SPAN_DECLARE(int) t38_core_send_indicator(t38_core_state_t *s, int indicator);

/*! \brief Find the delay to allow for HDLC flags after sending an indicator
    \param s The T.38 context.
    \param indicator The indicator to send.
    \return The delay to allow for initial HDLC flags after this indicator is sent. */
SPAN_DECLARE(int) t38_core_send_flags_delay(t38_core_state_t *s, int indicator);

/*! \brief Send a data packet
    \param s The T.38 context.
    \param data_type The packet's data type.
    \param field_type The packet's field type.
    \param field The message data content for the packet.
    \param field_len The length of the message data, in bytes.
    \param category The category of the packet being sent. This should be one of the values defined for t38_packet_categories_e.
    \return ??? */
SPAN_DECLARE(int) t38_core_send_data(t38_core_state_t *s, int data_type, int field_type, const uint8_t field[], int field_len, int category);

/*! \brief Send a data packet
    \param s The T.38 context.
    \param data_type The packet's data type.
    \param field The list of fields.
    \param fields The number of fields in the list.
    \param category The category of the packet being sent. This should be one of the values defined for t38_packet_categories_e.
    \return ??? */
SPAN_DECLARE(int) t38_core_send_data_multi_field(t38_core_state_t *s, int data_type, const t38_data_field_t field[], int fields, int category);

/*! \brief Process a received T.38 IFP packet.
    \param s The T.38 context.
    \param buf The packet contents.
    \param len The length of the packet contents.
    \param seq_no The packet sequence number.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t38_core_rx_ifp_packet(t38_core_state_t *s, const uint8_t *buf, int len, uint16_t seq_no);

/*! Set the method to be used for data rate management, as per the T.38 spec.
    \param s The T.38 context.
    \param method 1 for pass TCF across the T.38 link, 2 for handle TCF locally.
*/
SPAN_DECLARE(void) t38_set_data_rate_management_method(t38_core_state_t *s, int method);

/*! Set the data transport protocol.
    \param s The T.38 context.
    \param data_transport_protocol UDPTL, RTP or TPKT.
*/
SPAN_DECLARE(void) t38_set_data_transport_protocol(t38_core_state_t *s, int data_transport_protocol);

/*! Set the non-ECM fill bit removal mode.
    \param s The T.38 context.
    \param fill_bit_removal TRUE to remove fill bits across the T.38 link, else FALSE.
*/
SPAN_DECLARE(void) t38_set_fill_bit_removal(t38_core_state_t *s, int fill_bit_removal);

/*! Set the MMR transcoding mode.
    \param s The T.38 context.
    \param mmr_transcoding TRUE to transcode to MMR across the T.38 link, else FALSE.
*/
SPAN_DECLARE(void) t38_set_mmr_transcoding(t38_core_state_t *s, int mmr_transcoding);

/*! Set the JBIG transcoding mode.
    \param s The T.38 context.
    \param jbig_transcoding TRUE to transcode to JBIG across the T.38 link, else FALSE.
*/
SPAN_DECLARE(void) t38_set_jbig_transcoding(t38_core_state_t *s, int jbig_transcoding);

/*! Set the maximum buffer size for received data at the far end.
    \param s The T.38 context.
    \param max_buffer_size The maximum buffer size.
*/
SPAN_DECLARE(void) t38_set_max_buffer_size(t38_core_state_t *s, int max_buffer_size);

/*! Set the maximum size of an IFP packet that is acceptable by the far end.
    \param s The T.38 context.
    \param max_datagram_size The maximum IFP packet length, in bytes.
*/
SPAN_DECLARE(void) t38_set_max_datagram_size(t38_core_state_t *s, int max_datagram_size);

/*! \brief Send a data packet
    \param s The T.38 context.
    \param category The category of the packet being sent. This should be one of the values defined for t38_packet_categories_e.
    \param setting The repeat count for the category. This should be at least one for all categories other an indicator packets.
                   Zero is valid for indicator packets, as it suppresses the sending of indicator packets, as an application using
                   TCP for the transport would require. As the setting is passed through to the transmission channel, additional
                   information may be encoded in it, such as the redundancy depth for the particular packet category. */
SPAN_DECLARE(void) t38_set_redundancy_control(t38_core_state_t *s, int category, int setting);

SPAN_DECLARE(void) t38_set_fastest_image_data_rate(t38_core_state_t *s, int max_rate);

SPAN_DECLARE(int) t38_get_fastest_image_data_rate(t38_core_state_t *s);

/*! Set the T.38 version to be emulated.
    \param s The T.38 context.
    \param t38_version Version number, as in the T.38 spec.
*/
SPAN_DECLARE(void) t38_set_t38_version(t38_core_state_t *s, int t38_version);

/*! Set the sequence number handling option.
    \param s The T.38 context.
    \param check TRUE to check sequence numbers, and handle gaps reasonably. FALSE
           for no sequence number processing (e.g. for TPKT over TCP transport).
*/
SPAN_DECLARE(void) t38_set_sequence_number_handling(t38_core_state_t *s, int check);

/*! Set the TEP handling option.
    \param s The T.38 context.
    \param allow_for_tep TRUE to allow for TEP playout, else FALSE.
*/
SPAN_DECLARE(void) t38_set_tep_handling(t38_core_state_t *s, int allow_for_tep);

/*! Get a pointer to the logging context associated with a T.38 context.
    \brief Get a pointer to the logging context associated with a T.38 context.
    \param s The T.38 context.
    \return A pointer to the logging context, or NULL.
*/
SPAN_DECLARE(logging_state_t *) t38_core_get_logging_state(t38_core_state_t *s);

/*! Initialise a T.38 core context.
    \brief Initialise a T.38 core context.
    \param s The T.38 context.
    \param rx_indicator_handler Receive indicator handling routine.
    \param rx_data_handler Receive data packet handling routine.
    \param rx_rx_missing_handler Missing receive packet handling routine.
    \param rx_packet_user_data An opaque pointer passed to the rx packet handling routines.
    \param tx_packet_handler Packet transmit handling routine.
    \param tx_packet_user_data An opaque pointer passed to the tx_packet_handler.
    \return A pointer to the T.38 context, or NULL if there was a problem. */
SPAN_DECLARE(t38_core_state_t *) t38_core_init(t38_core_state_t *s,
                                               t38_rx_indicator_handler_t *rx_indicator_handler,
                                               t38_rx_data_handler_t *rx_data_handler,
                                               t38_rx_missing_handler_t *rx_missing_handler,
                                               void *rx_user_data,
                                               t38_tx_packet_handler_t *tx_packet_handler,
                                               void *tx_packet_user_data);

/*! Release a signaling tone transmitter context.
    \brief Release a signaling tone transmitter context.
    \param s The T.38 context.
    \return 0 for OK */
SPAN_DECLARE(int) t38_core_release(t38_core_state_t *s);

/*! Free a signaling tone transmitter context.
    \brief Free a signaling tone transmitter context.
    \param s The T.38 context.
    \return 0 for OK */
SPAN_DECLARE(int) t38_core_free(t38_core_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
