/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t30.h - definitions for T.30 fax processing
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
 * $Id: t30.h,v 1.126.4.1 2009/12/19 09:47:56 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T30_H_)
#define _SPANDSP_T30_H_

/*! \page t30_page T.30 FAX protocol handling

\section t30_page_sec_1 What does it do?
The T.30 protocol is the core protocol used for FAX transmission. This module
implements most of its key featrues. It does not interface to the outside work.
Seperate modules do that for T.38, analogue line, and other forms of FAX
communication.

Current features of this module include:

    - FAXing to and from multi-page TIFF/F files, whose images are one of the standard
      FAX sizes.
    - V.27ter, V.29 and V.17 modes (2400bps, to 14,400bps).
    - T.4 1D (MH), T.4 2D,(MR) and T.6 (MMR) compression.
    - Error correction mode (ECM).
    - All standard horizonal resolutions (R8, R16, 300dpi, 600dpi, 800dpi, 1200dpi).
    - All standard vertical resolutions (standard, fine, superfine, 300dpi, 600dpi, 800dpi, 1200dpi).
    - All standard page widths (A4, B4, A3).
    - All standard page lengths (A4, B4, North American letter, North American legal, continuous).
    - Monitoring and sending identifier strings (CSI, TSI, and CIG).
    - Monitoring and sending sub-address strings (SUB).
    - Monitoring and sending polling sub-addresses (SEP).
    - Monitoring and sending polled sub-addresses (PSA).
    - Monitoring and sending sender identifications (SID).
    - Monitoring and sending passwords (PWD).
    - Monitoring of non-standard facility frames (NSF, NSC, and NSS).
    - Sending custom non-standard facility frames (NSF, NSC, and NSS).
    - Analogue modem and T.38 operation.

\section t30_page_sec_2 How does it work?

Some of the following is paraphrased from some notes found a while ago on the Internet.
I cannot remember exactly where they came from, but they are useful.

\subsection t30_page_sec_2a The answer (CED) tone

The T.30 standard says an answering fax device must send CED (a 2100Hz tone) for
approximately 3 seconds before sending the first handshake message. Some machines
send an 1100Hz or 1850Hz tone, and some send no tone at all. In fact, this answer
tone is so unpredictable, it cannot really be used. It should, however, always be
generated according to the specification.

\subsection t30_page_sec_2b Common Timing Deviations

The T.30 spec. specifies a number of time-outs. For example, after dialing a number,
a calling fax system should listen for a response for 35 seconds before giving up.
These time-out periods are as follows: 

    - T1 - 35+-5s: the maximum time for which two fax system will attempt to identify each other
    - T2 - 6+-1s:  a time-out used to start the sequence for changing transmit parameters
    - T3 - 10+-5s: a time-out used in handling operator interrupts
    - T5 - 60+-5s: a time-out used in error correction mode

These time-outs are sometimes misinterpreted. In addition, they are routinely
ignored, sometimes with good reason. For example, after placing a call, the
calling fax system is supposed to wait for 35 seconds before giving up. If the
answering unit does not answer on the first ring or if a voice answering machine
is connected to the line, or if there are many delays through the network,
the delay before answer can be much longer than 35 seconds. 

Fax units that support error correction mode (ECM) can respond to a post-image
handshake message with a receiver not ready (RNR) message. The calling unit then
queries the receiving fax unit with a receiver ready (RR) message. If the
answering unit is still busy (printing for example), it will repeat the RNR
message. According to the T.30 standard, this sequence (RR/RNR RR/RNR) can be
repeated for up to the end of T5 (60+-5s). However, many fax systems
ignore the time-out and will continue the sequence indefinitely, unless the user
manually overrides. 

All the time-outs are subject to alteration, and sometimes misuse. Good T.30
implementations must do the right thing, and tolerate others doing the wrong thing.

\subsection t30_page_sec_2c Variations in the inter-carrier gap

T.30 specifies 75+-20ms of silence between signals using different modulation
schemes. Examples are between the end of a DCS signal and the start of a TCF signal,
and between the end of an image and the start of a post-image signal. Many fax systems
violate this requirement, especially for the silent period between DCS and TCF.
This may be stretched to well over 100ms. If this period is too long, it can interfere with
handshake signal error recovery, should a packet be corrupted on the line. Systems
should ensure they stay within the prescribed T.30 limits, and be tolerant of others
being out of spec.. 

\subsection t30_page_sec_2d Other timing variations

Testing is required to determine the ability of a fax system to handle
variations in the duration of pauses between unacknowledged handshake message
repetitions, and also in the pauses between the receipt of a handshake command and
the start of a response to that command. In order to reduce the total
transmission time, many fax systems start sending a response message before the
end of the command has been received. 

\subsection t30_page_sec_2e Other deviations from the T.30 standard

There are many other commonly encountered variations between machines, including:

    - frame sequence deviations
    - preamble and flag sequence variations
    - improper EOM usage
    - unusual data rate fallback sequences
    - common training pattern detection algorithms
    - image transmission deviations
    - use of the talker echo protect tone
    - image padding and short lines
    - RTP/RTN handshake message usage
    - long duration lines
    - nonstandard disconnect sequences
    - DCN usage
*/

/*! The maximum length of a DIS, DTC or DCS frame */
#define T30_MAX_DIS_DTC_DCS_LEN     22
/*! The maximum length of the body of an ident string */
#define T30_MAX_IDENT_LEN           20
/*! The maximum length of the user string to insert in page headers */
#define T30_MAX_PAGE_HEADER_INFO    50

typedef struct t30_state_s t30_state_t;

/*!
    T.30 phase B callback handler. This handler can be used to process addition
    information available in some FAX calls, such as passwords. The callback handler
    can access whatever additional information might have been received, using
    t30_get_received_info().
    \brief T.30 phase B callback handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param result The phase B event code.
    \return The new status. Normally, T30_ERR_OK is returned.
*/
typedef int (t30_phase_b_handler_t)(t30_state_t *s, void *user_data, int result);

/*!
    T.30 phase D callback handler.
    \brief T.30 phase D callback handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param result The phase D event code.
    \return The new status. Normally, T30_ERR_OK is returned.
*/
typedef int (t30_phase_d_handler_t)(t30_state_t *s, void *user_data, int result);

/*!
    T.30 phase E callback handler.
    \brief T.30 phase E callback handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param completion_code The phase E completion code.
*/
typedef void (t30_phase_e_handler_t)(t30_state_t *s, void *user_data, int completion_code);

/*!
    T.30 real time frame handler.
    \brief T.30 real time frame handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param direction TRUE for incoming, FALSE for outgoing.
    \param msg The HDLC message.
    \param len The length of the message.
*/
typedef void (t30_real_time_frame_handler_t)(t30_state_t *s,
                                             void *user_data,
                                             int direction,
                                             const uint8_t msg[],
                                             int len);

/*!
    T.30 document handler.
    \brief T.30 document handler.
    \param s The T.30 context.
    \param user_data An opaque pointer.
    \param result The document event code.
*/
typedef int (t30_document_handler_t)(t30_state_t *s, void *user_data, int status);

/*!
    T.30 set a receive or transmit type handler.
    \brief T.30 set a receive or transmit type handler.
    \param user_data An opaque pointer.
    \param type The modem, tone or silence to be sent or received.
    \param bit_rate The bit rate of the modem to be sent or received.
    \param short_train TRUE if the short training sequence should be used (where one exists).
    \param use_hdlc FALSE for bit stream, TRUE for HDLC framing.
*/
typedef void (t30_set_handler_t)(void *user_data, int type, int bit_rate, int short_train, int use_hdlc);

/*!
    T.30 send HDLC handler.
    \brief T.30 send HDLC handler.
    \param user_data An opaque pointer.
    \param msg The HDLC message.
    \param len The length of the message.
*/
typedef void (t30_send_hdlc_handler_t)(void *user_data, const uint8_t msg[], int len);

/*!
    T.30 protocol completion codes, at phase E.
*/
enum
{
    T30_ERR_OK = 0,             /*! OK */

    /* Link problems */
    T30_ERR_CEDTONE,            /*! The CED tone exceeded 5s */
    T30_ERR_T0_EXPIRED,         /*! Timed out waiting for initial communication */
    T30_ERR_T1_EXPIRED,         /*! Timed out waiting for the first message */
    T30_ERR_T3_EXPIRED,         /*! Timed out waiting for procedural interrupt */
    T30_ERR_HDLC_CARRIER,       /*! The HDLC carrier did not stop in a timely manner */
    T30_ERR_CANNOT_TRAIN,       /*! Failed to train with any of the compatible modems */
    T30_ERR_OPER_INT_FAIL,      /*! Operator intervention failed */
    T30_ERR_INCOMPATIBLE,       /*! Far end is not compatible */
    T30_ERR_RX_INCAPABLE,       /*! Far end is not able to receive */
    T30_ERR_TX_INCAPABLE,       /*! Far end is not able to transmit */
    T30_ERR_NORESSUPPORT,       /*! Far end cannot receive at the resolution of the image */
    T30_ERR_NOSIZESUPPORT,      /*! Far end cannot receive at the size of image */
    T30_ERR_UNEXPECTED,         /*! Unexpected message received */

    /* Phase E status values returned to a transmitter */
    T30_ERR_TX_BADDCS,          /*! Received bad response to DCS or training */
    T30_ERR_TX_BADPG,           /*! Received a DCN from remote after sending a page */
    T30_ERR_TX_ECMPHD,          /*! Invalid ECM response received from receiver */
    T30_ERR_TX_GOTDCN,          /*! Received a DCN while waiting for a DIS */
    T30_ERR_TX_INVALRSP,        /*! Invalid response after sending a page */
    T30_ERR_TX_NODIS,           /*! Received other than DIS while waiting for DIS */
    T30_ERR_TX_PHBDEAD,         /*! Received no response to DCS, training or TCF */
    T30_ERR_TX_PHDDEAD,         /*! No response after sending a page */
    T30_ERR_TX_T5EXP,           /*! Timed out waiting for receiver ready (ECM mode) */

    /* Phase E status values returned to a receiver */
    T30_ERR_RX_ECMPHD,          /*! Invalid ECM response received from transmitter */
    T30_ERR_RX_GOTDCS,          /*! DCS received while waiting for DTC */
    T30_ERR_RX_INVALCMD,        /*! Unexpected command after page received */
    T30_ERR_RX_NOCARRIER,       /*! Carrier lost during fax receive */
    T30_ERR_RX_NOEOL,           /*! Timed out while waiting for EOL (end Of line) */
    T30_ERR_RX_NOFAX,           /*! Timed out while waiting for first line */
    T30_ERR_RX_T2EXPDCN,        /*! Timer T2 expired while waiting for DCN */
    T30_ERR_RX_T2EXPD,          /*! Timer T2 expired while waiting for phase D */
    T30_ERR_RX_T2EXPFAX,        /*! Timer T2 expired while waiting for fax page */
    T30_ERR_RX_T2EXPMPS,        /*! Timer T2 expired while waiting for next fax page */
    T30_ERR_RX_T2EXPRR,         /*! Timer T2 expired while waiting for RR command */
    T30_ERR_RX_T2EXP,           /*! Timer T2 expired while waiting for NSS, DCS or MCF */
    T30_ERR_RX_DCNWHY,          /*! Unexpected DCN while waiting for DCS or DIS */
    T30_ERR_RX_DCNDATA,         /*! Unexpected DCN while waiting for image data */
    T30_ERR_RX_DCNFAX,          /*! Unexpected DCN while waiting for EOM, EOP or MPS */
    T30_ERR_RX_DCNPHD,          /*! Unexpected DCN after EOM or MPS sequence */
    T30_ERR_RX_DCNRRD,          /*! Unexpected DCN after RR/RNR sequence */
    T30_ERR_RX_DCNNORTN,        /*! Unexpected DCN after requested retransmission */

    /* TIFF file problems */
    T30_ERR_FILEERROR,          /*! TIFF/F file cannot be opened */
    T30_ERR_NOPAGE,             /*! TIFF/F page not found */
    T30_ERR_BADTIFF,            /*! TIFF/F format is not compatible */
    T30_ERR_BADPAGE,            /*! TIFF/F page number tag missing */
    T30_ERR_BADTAG,             /*! Incorrect values for TIFF/F tags */
    T30_ERR_BADTIFFHDR,         /*! Bad TIFF/F header - incorrect values in fields */
    T30_ERR_NOMEM,              /*! Cannot allocate memory for more pages */
    
    /* General problems */
    T30_ERR_RETRYDCN,           /*! Disconnected after permitted retries */
    T30_ERR_CALLDROPPED,        /*! The call dropped prematurely */
    
    /* Feature negotiation issues */
    T30_ERR_NOPOLL,             /*! Poll not accepted */
    T30_ERR_IDENT_UNACCEPTABLE, /*! Far end's ident is not acceptable */
    T30_ERR_SUB_UNACCEPTABLE,   /*! Far end's sub-address is not acceptable */
    T30_ERR_SEP_UNACCEPTABLE,   /*! Far end's selective polling address is not acceptable */
    T30_ERR_PSA_UNACCEPTABLE,   /*! Far end's polled sub-address is not acceptable */
    T30_ERR_SID_UNACCEPTABLE,   /*! Far end's sender identification is not acceptable */
    T30_ERR_PWD_UNACCEPTABLE,   /*! Far end's password is not acceptable */
    T30_ERR_TSA_UNACCEPTABLE,   /*! Far end's transmitting subscriber internet address is not acceptable */
    T30_ERR_IRA_UNACCEPTABLE,   /*! Far end's internet routing address is not acceptable */
    T30_ERR_CIA_UNACCEPTABLE,   /*! Far end's calling subscriber internet address is not acceptable */
    T30_ERR_ISP_UNACCEPTABLE,   /*! Far end's internet selective polling address is not acceptable */
    T30_ERR_CSA_UNACCEPTABLE    /*! Far end's called subscriber internet address is not acceptable */
};

/*!
    I/O modes for the T.30 protocol.
    These are allocated such that the lower 4 bits represents the variant of the modem - e.g. the
    particular bit rate selected.
*/
enum
{
    T30_MODEM_NONE = 0,
    T30_MODEM_PAUSE,
    T30_MODEM_CED,
    T30_MODEM_CNG,
    T30_MODEM_V21,
    T30_MODEM_V27TER,
    T30_MODEM_V29,
    T30_MODEM_V17,
    T30_MODEM_DONE
};

enum
{
    T30_FRONT_END_SEND_STEP_COMPLETE = 0,
    /*! The current receive has completed. This is only needed to report an
        unexpected end of the receive operation, as might happen with T.38
        dying. */
    T30_FRONT_END_RECEIVE_COMPLETE,
    T30_FRONT_END_SIGNAL_PRESENT,
    T30_FRONT_END_SIGNAL_ABSENT,
    T30_FRONT_END_CED_PRESENT,
    T30_FRONT_END_CNG_PRESENT
};

enum
{
    /*! Support the V.27ter modem (2400, and 4800bps) for image transfer. */
    T30_SUPPORT_V27TER = 0x01,
    /*! Support the V.29 modem (9600, and 7200bps) for image transfer. */
    T30_SUPPORT_V29 = 0x02,
    /*! Support the V.17 modem (14400, 12000, 9600 and 7200bps) for image transfer. */
    T30_SUPPORT_V17 = 0x04,
    /*! Support the V.34 modem (up to 33,600bps) for image transfer. */
    T30_SUPPORT_V34 = 0x08,
    /*! Support the Internet aware FAX mode (no bit rate limit) for image transfer. */
    T30_SUPPORT_IAF = 0x10
};

enum
{
    /*! No compression */
    T30_SUPPORT_NO_COMPRESSION = 0x01,
    /*! T.1 1D compression */
    T30_SUPPORT_T4_1D_COMPRESSION = 0x02,
    /*! T.4 2D compression */
    T30_SUPPORT_T4_2D_COMPRESSION = 0x04,
    /*! T.6 2D compression */
    T30_SUPPORT_T6_COMPRESSION = 0x08,
    /*! T.85 monochrome JBIG compression */
    T30_SUPPORT_T85_COMPRESSION = 0x10,
    /*! T.43 colour JBIG compression */
    T30_SUPPORT_T43_COMPRESSION = 0x20,
    /*! T.45 run length colour compression */
    T30_SUPPORT_T45_COMPRESSION = 0x40,
    /*! T.81 + T.30 Annex E colour JPEG compression */
    T30_SUPPORT_T81_COMPRESSION = 0x80,
    /*! T.81 + T.30 Annex K colour sYCC-JPEG compression */
    T30_SUPPORT_SYCC_T81_COMPRESSION = 0x100,
    /*! T.88 monochrome JBIG2 compression */
    T30_SUPPORT_T88_COMPRESSION = 0x200
};

enum
{
    /*! Support standard FAX Y-resolution 98/100dpi */
    T30_SUPPORT_STANDARD_RESOLUTION = 0x01,
    /*! Support fine FAX Y-resolution 196/200dpi */
    T30_SUPPORT_FINE_RESOLUTION = 0x02,
    /*! Support super-fine FAX Y-resolution 392/400dpi */
    T30_SUPPORT_SUPERFINE_RESOLUTION = 0x04,

    /*! Support half FAX X-resolution 100/102dpi */
    T30_SUPPORT_R4_RESOLUTION = 0x10000,
    /*! Support standard FAX X-resolution 200/204dpi */
    T30_SUPPORT_R8_RESOLUTION = 0x20000,
    /*! Support double FAX X-resolution 400dpi */
    T30_SUPPORT_R16_RESOLUTION = 0x40000,

    /*! Support 300dpi x 300 dpi */
    T30_SUPPORT_300_300_RESOLUTION = 0x100000,
    /*! Support 400dpi x 400 dpi */
    T30_SUPPORT_400_400_RESOLUTION = 0x200000,
    /*! Support 600dpi x 600 dpi */
    T30_SUPPORT_600_600_RESOLUTION = 0x400000,
    /*! Support 1200dpi x 1200 dpi */
    T30_SUPPORT_1200_1200_RESOLUTION = 0x800000,
    /*! Support 300dpi x 600 dpi */
    T30_SUPPORT_300_600_RESOLUTION = 0x1000000,
    /*! Support 400dpi x 800 dpi */
    T30_SUPPORT_400_800_RESOLUTION = 0x2000000,
    /*! Support 600dpi x 1200 dpi */
    T30_SUPPORT_600_1200_RESOLUTION = 0x4000000
};

enum
{
    T30_SUPPORT_215MM_WIDTH = 0x01,
    T30_SUPPORT_255MM_WIDTH = 0x02,
    T30_SUPPORT_303MM_WIDTH = 0x04,

    T30_SUPPORT_UNLIMITED_LENGTH = 0x10000,
    T30_SUPPORT_A4_LENGTH = 0x20000,
    T30_SUPPORT_B4_LENGTH = 0x40000,
    T30_SUPPORT_US_LETTER_LENGTH = 0x80000,
    T30_SUPPORT_US_LEGAL_LENGTH = 0x100000
};

enum
{
    /*! Enable support of identification, through the SID and/or PWD frames. */
    T30_SUPPORT_IDENTIFICATION = 0x01,
    /*! Enable support of selective polling, through the SEP frame. */
    T30_SUPPORT_SELECTIVE_POLLING = 0x02,
    /*! Enable support of polling sub-addressing, through the PSA frame. */
    T30_SUPPORT_POLLED_SUB_ADDRESSING = 0x04,
    /*! Enable support of multiple selective polling, through repeated used of the SEP and PSA frames. */
    T30_SUPPORT_MULTIPLE_SELECTIVE_POLLING = 0x08,
    /*! Enable support of sub-addressing, through the SUB frame. */
    T30_SUPPORT_SUB_ADDRESSING = 0x10,
    /*! Enable support of transmitting subscriber internet address, through the TSA frame. */
    T30_SUPPORT_TRANSMITTING_SUBSCRIBER_INTERNET_ADDRESS = 0x20,
    /*! Enable support of internet routing address, through the IRA frame. */
    T30_SUPPORT_INTERNET_ROUTING_ADDRESS = 0x40,
    /*! Enable support of calling subscriber internet address, through the CIA frame. */
    T30_SUPPORT_CALLING_SUBSCRIBER_INTERNET_ADDRESS = 0x80,
    /*! Enable support of internet selective polling address, through the ISP frame. */
    T30_SUPPORT_INTERNET_SELECTIVE_POLLING_ADDRESS = 0x100,
    /*! Enable support of called subscriber internet address, through the CSA frame. */
    T30_SUPPORT_CALLED_SUBSCRIBER_INTERNET_ADDRESS = 0x200,
    /*! Enable support of the field not valid (FNV) frame. */
    T30_SUPPORT_FIELD_NOT_VALID = 0x400,
    /*! Enable support of the command repeat (CRP) frame. */
    T30_SUPPORT_COMMAND_REPEAT = 0x800
};

enum
{
    T30_IAF_MODE_T37 = 0x01,
    T30_IAF_MODE_T38 = 0x02,
    T30_IAF_MODE_FLOW_CONTROL = 0x04,
    /*! Continuous flow mode means data is sent as fast as possible, usually across
        the Internet, where speed is not constrained by a PSTN modem. */
    T30_IAF_MODE_CONTINUOUS_FLOW = 0x08,
    /*! No TCF means TCF is not exchanged. The end points must sort out usable speed
        issues locally. */
    T30_IAF_MODE_NO_TCF = 0x10,
    /*! No fill bits means do not insert fill bits, even if the T.30 messages request
        them. */
    T30_IAF_MODE_NO_FILL_BITS = 0x20,
    /*! No indicators means do not send indicator messages when using T.38. */
    T30_IAF_MODE_NO_INDICATORS = 0x40,
    /*! Use relaxed timers for T.38. This is appropriate when using TCP/TPKT for T.38,
        as there is no point in anything but a long backstop timeout in such a mode. */
    T30_IAF_MODE_RELAXED_TIMERS = 0x80
};

typedef struct
{
    /*! \brief The identifier string (CSI, TSI, CIG). */
    char ident[T30_MAX_IDENT_LEN + 1];
    /*! \brief The sub-address string (SUB). */
    char sub_address[T30_MAX_IDENT_LEN + 1];
    /*! \brief The selective polling sub-address (SEP). */
    char selective_polling_address[T30_MAX_IDENT_LEN + 1];
    /*! \brief The polled sub-address (PSA). */
    char polled_sub_address[T30_MAX_IDENT_LEN + 1];
    /*! \brief The sender identification (SID). */
    char sender_ident[T30_MAX_IDENT_LEN + 1];
    /*! \brief The password (PWD). */
    char password[T30_MAX_IDENT_LEN + 1];
    /*! \brief Non-standard facilities (NSF). */
    uint8_t *nsf;
    size_t nsf_len;
    /*! \brief Non-standard facilities command (NSC). */
    uint8_t *nsc;
    size_t nsc_len;
    /*! \brief Non-standard facilities set-up (NSS). */
    uint8_t *nss;
    size_t nss_len;
    /*! \brief Transmitting subscriber internet address (TSA). */
    int tsa_type;
    char *tsa;
    size_t tsa_len;
    /*! \brief Internet routing address (IRA). */
    int ira_type;
    char *ira;
    size_t ira_len;
    /*! \brief Calling subscriber internet address (CIA). */
    int cia_type;
    char *cia;
    size_t cia_len;
    /*! \brief Internet selective polling address (ISP). */
    int isp_type;
    char *isp;
    size_t isp_len;
    /*! \brief Called subscriber internet address (CSA). */
    int csa_type;
    char *csa;
    size_t csa_len;
} t30_exchanged_info_t;

typedef struct
{
    /*! \brief The current bit rate for image transfer. */
    int bit_rate;
    /*! \brief TRUE if error correcting mode is used. */
    int error_correcting_mode;
    /*! \brief The number of pages sent so far. */
    int pages_tx;
    /*! \brief The number of pages received so far. */
    int pages_rx;
    /*! \brief The number of pages in the file (<0 if not known). */
    int pages_in_file;
    /*! \brief The horizontal column-to-column resolution of the most recent page, in pixels per metre */
    int x_resolution;
    /*! \brief The vertical row-to-row resolution of the most recent page, in pixels per metre */
    int y_resolution;
    /*! \brief The number of horizontal pixels in the most recent page. */
    int width;
    /*! \brief The number of vertical pixels in the most recent page. */
    int length;
    /*! \brief The size of the image, in bytes */
    int image_size;
    /*! \brief The type of compression used between the FAX machines */
    int encoding;
    /*! \brief The number of bad pixel rows in the most recent page. */
    int bad_rows;
    /*! \brief The largest number of bad pixel rows in a block in the most recent page. */
    int longest_bad_row_run;
    /*! \brief The number of HDLC frame retries, if error correcting mode is used. */
    int error_correcting_mode_retries;
    /*! \brief Current status */
    int current_status;
} t30_stats_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a T.30 context.
    \brief Initialise a T.30 context.
    \param s The T.30 context.
    \param calling_party TRUE if the context is for a calling party. FALSE if the
           context is for an answering party.
    \param set_rx_type_handler
    \param set_rx_type_user_data
    \param set_tx_type_handler
    \param set_tx_type_user_data
    \param send_hdlc_handler
    \param send_hdlc_user_data
    \return A pointer to the context, or NULL if there was a problem. */
SPAN_DECLARE(t30_state_t *) t30_init(t30_state_t *s,
                                     int calling_party,
                                     t30_set_handler_t *set_rx_type_handler,
                                     void *set_rx_type_user_data,
                                     t30_set_handler_t *set_tx_type_handler,
                                     void *set_tx_type_user_data,
                                     t30_send_hdlc_handler_t *send_hdlc_handler,
                                     void *send_hdlc_user_data);

/*! Release a T.30 context.
    \brief Release a T.30 context.
    \param s The T.30 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_release(t30_state_t *s);

/*! Free a T.30 context.
    \brief Free a T.30 context.
    \param s The T.30 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_free(t30_state_t *s);

/*! Restart a T.30 context.
    \brief Restart a T.30 context.
    \param s The T.30 context.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_restart(t30_state_t *s);

/*! Check if a T.30 call is still active. This may be used to regularly poll
    if the job has finished.
    \brief Check if a T.30 call is still active.
    \param s The T.30 context.
    \return TRUE for call still active, or FALSE for call completed. */
SPAN_DECLARE(int) t30_call_active(t30_state_t *s);

/*! Cleanup a T.30 context if the call terminates.
    \brief Cleanup a T.30 context if the call terminates.
    \param s The T.30 context. */
SPAN_DECLARE(void) t30_terminate(t30_state_t *s);

/*! Inform the T.30 engine of a status change in the front end (end of tx, rx signal change, etc.).
    \brief Inform the T.30 engine of a status change in the front end (end of tx, rx signal change, etc.).
    \param user_data The T.30 context.
    \param status The type of status change which occured. */
SPAN_DECLARE(void) t30_front_end_status(void *user_data, int status);

/*! Get a bit of received non-ECM image data.
    \brief Get a bit of received non-ECM image data.
    \param user_data An opaque pointer, which must point to the T.30 context.
    \return The next bit to transmit. */
SPAN_DECLARE_NONSTD(int) t30_non_ecm_get_bit(void *user_data);

/*! Get a byte of received non-ECM image data.
    \brief Get a byte of received non-ECM image data.
    \param user_data An opaque pointer, which must point to the T.30 context.
    \return The next byte to transmit. */
SPAN_DECLARE(int) t30_non_ecm_get_byte(void *user_data);

/*! Get a chunk of received non-ECM image data.
    \brief Get a bit of received non-ECM image data.
    \param user_data An opaque pointer, which must point to the T.30 context.
    \param buf The buffer to contain the data.
    \param max_len The maximum length of the chunk.
    \return The actual length of the chunk. */
SPAN_DECLARE(int) t30_non_ecm_get_chunk(void *user_data, uint8_t buf[], int max_len);

/*! Process a bit of received non-ECM image data.
    \brief Process a bit of received non-ECM image data
    \param user_data An opaque pointer, which must point to the T.30 context.
    \param bit The received bit. */
SPAN_DECLARE_NONSTD(void) t30_non_ecm_put_bit(void *user_data, int bit);

/*! Process a byte of received non-ECM image data.
    \brief Process a byte of received non-ECM image data
    \param user_data An opaque pointer, which must point to the T.30 context.
    \param byte The received byte. */
SPAN_DECLARE(void) t30_non_ecm_put_byte(void *user_data, int byte);

/*! Process a chunk of received non-ECM image data.
    \brief Process a chunk of received non-ECM image data
    \param user_data An opaque pointer, which must point to the T.30 context.
    \param buf The buffer containing the received data.
    \param len The length of the data in buf. */
SPAN_DECLARE(void) t30_non_ecm_put_chunk(void *user_data, const uint8_t buf[], int len);

/*! Process a received HDLC frame.
    \brief Process a received HDLC frame.
    \param user_data The T.30 context.
    \param msg The HDLC message.
    \param len The length of the message, in octets.
    \param ok TRUE if the frame was received without error. */
SPAN_DECLARE_NONSTD(void) t30_hdlc_accept(void *user_data, const uint8_t msg[], int len, int ok);

/*! Report the passage of time to the T.30 engine.
    \brief Report the passage of time to the T.30 engine.
    \param s The T.30 context.
    \param samples The time change in 1/8000th second steps. */
SPAN_DECLARE(void) t30_timer_update(t30_state_t *s, int samples);

/*! Get the current transfer statistics for the file being sent or received.
    \brief Get the current transfer statistics.
    \param s The T.30 context.
    \param t A pointer to a buffer for the statistics. */
SPAN_DECLARE(void) t30_get_transfer_statistics(t30_state_t *s, t30_stats_t *t);

/*! Request a local interrupt of FAX exchange.
    \brief Request a local interrupt of FAX exchange.
    \param s The T.30 context.
    \param state TRUE to enable interrupt request, else FALSE. */
SPAN_DECLARE(void) t30_local_interrupt_request(t30_state_t *s, int state);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
