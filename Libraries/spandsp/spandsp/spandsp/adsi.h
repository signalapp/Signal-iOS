/*
 * SpanDSP - a series of DSP components for telephony
 *
 * adsi.h - Analogue display services interface and other call ID related handling.
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
 * $Id: adsi.h,v 1.40 2009/05/22 16:39:01 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_ADSI_H_)
#define _SPANDSP_ADSI_H_

/*! \page adsi_page ADSI transmission and reception
\section adsi_page_sec_1 What does it do?
Although ADSI has a specific meaning in some places, the term is used here to indicate
any form of Analogue Display Service Interface, which includes caller ID, SMS, and others.

The ADSI module provides for the transmission and reception of ADSI messages
in various formats. Currently, the supported formats are:

    - Bellcore/Telcordia GR-30 CORE CLASS (Custom Local Area Signaling Services) standard
      (North America, Australia, China, Taiwan, and Hong Kong).

    - ETSI ETS 300 648, ETS 300 659-1 CLIP (Calling Line Identity Presentation) FSK standard
      (France, Germany, Norway, Italy, Spain, South Africa, Turkey, and the UK).

    - ETSI Caller-ID support for the UK, British Telecom SIN227 and SIN242.

    - ETSI ETS 300 648, ETS 300 659-1 CLIP (Calling Line Identity Presentation) DTMF standard
      variant 1 (Belgium, Brazil, Denmark, Finland, Iceland, India, Netherlands, Saudi Arabia,
      Sweden and Uruguay).
    
    - ETSI ETS 300 648, ETS 300 659-1 CLIP (Calling Line Identity Presentation) DTMF standard
      variant 2 (Denmark and Holland).
    
    - ETSI ETS 300 648, ETS 300 659-1 CLIP (Calling Line Identity Presentation) DTMF standard
      variant 3.
    
    - ETSI ETS 300 648, ETS 300 659-1 CLIP (Calling Line Identity Presentation) DTMF standard
      variant 4. (Taiwan and Kuwait).
    
    - ETSI Caller-ID support in UK (British Telecom), British Telecomm SIN227, SIN242.

    - Nippon Telegraph & Telephone Corporation JCLIP (Japanese Calling Line Identity
      Presentation) standard.

    - Telecommunications Authority of Singapore ACLIP (Analog Calling Line Identity
      Presentation) standard.

    - TDD (Telecommunications Device for the Deaf).

\section adsi_page_sec_2 How does it work?

\section adsi_page_sec_2a The Bellcore CLASS specification
Most FSK based CLI formats are similar to the US CLASS one, which is as follows:

The alert tone for CLI during a call is at least 100ms of silence, then
2130Hz + 2750Hz for 88ms to 110ms. When CLI is presented at ringing time,
this tone is not sent. In the US, CLI is usually sent between the first
two rings. This silence period is long in the US, so the message fits easily.
In other places, where the standard ring tone has much smaller silences,
a line voltage reversal is used to wake up a power saving receiver, then the
message is sent, then the phone begins to ring.
    
The message is sent using a Bell 202 FSK modem. The data rate is 1200 bits
per second. The message protocol uses 8-bit data words (bytes), each bounded
by a start bit and a stop bit.

Channel     Carrier     Message     Message     Data        Checksum
Seizure     Signal      Type        Length      Word(s)     Word
Signal                  Word        Word
    
\section adsi_page_sec_2a1 CHANNEL SEIZURE SIGNAL
The channel seizure is 30 continuous bytes of 55h (01010101), including
the start and stop bits (i.e. 300 bits of alternations in total).
This provides a detectable alternating function to the CPE (i.e. the
modem data pump).
    
\section adsi_page_sec_2a2 CARRIER SIGNAL
The carrier signal consists of 180 bits of 1s. This may be reduced to 80
bits of 1s for caller ID on call waiting.
    
\section adsi_page_sec_2a3 MESSAGE TYPE WORD
Various message types are defined. The commonest ones for the US CLASS 
standard are:

    - Type 0x04 (SDMF) - single data message. Simple caller ID (CND)
    - Type 0x80 (MDMF) - multiple data message. A more flexible caller ID,
                         with extra information.

Other messages support message waiting, for voice mail, and other display features. 

\section adsi_page_sec_2a4 MESSAGE LENGTH WORD
The message length word specifies the total number of data words
to follow.
    
\section adsi_page_sec_2a5 DATA WORDS
The data words contain the actual message.
    
\section adsi_page_sec_2a6 CHECKSUM WORD
The Checksum Word contains the twos complement of the modulo 256
sum of the other words in the data message (i.e., message type,
message length, and data words).  The receiving equipment may
calculate the modulo 256 sum of the received words and add this
sum to the received checksum word.  A result of zero generally
indicates that the message was correctly received.  Message
retransmission is not supported. The sumcheck word should be followed
by a minimum of two stop bits.

\section adsi_page_sec_2b The ETSI CLIP specification
The ETSI CLIP specification uses similar messages to the Bellcore specification.
They are not, however, identical. First, ETSI use the V.23 modem standard, rather
than Bell 202. Second, different fields, and different message types are available.

The wake up indication generally differs from the Bellcore specification, to
accomodate differences in European ring cadences.

\section adsi_page_sec_2c The ETSI caller ID by DTMF specification
CLI by DTMF is usually sent in a very simple way. The exchange does not give
any prior warning (no reversal, or ring) to wake up the receiver. It just
sends a string of DTMF digits. Around the world several variants of this
basic scheme are used.

One variant of the digit string is used in Belgium, Brazil, Denmark, Finland, Iceland,
India, Netherlands, Saudi Arabia, Sweden and Uruguay:

    - A<caller's phone number>D<redirected number>B<special information>C

Each of these fields may be omitted. The following special information codes are defined

    - "00" indicates the calling party number is not available.
    - "10" indicates that the presentation of the calling party number is restricted.

A second variant of the digit string is one of the following:

    - A<caller's phone number>#
    - D1#     Number not available because the caller has restricted it.
    - D2#     Number not available because the call is international.
    - D3#     Number not available due to technical reasons.

A third variant of the digit string is used in Taiwan and Kuwait:

    - D<caller's phone number>C

A forth variant of the digit string is used in Denmark and Holland:

    - <caller's phone number>#

There is no distinctive start marker in this format.

\section adsi_page_sec_2d The Japanese specification from NTT

The Japanese caller ID specification is considerably different from any of the others. It
uses V.23 modem signals, but the message structure is uniqeue. Also, the message is delivered
while off hook. This results in a sequence

    - The phone line rings
    - CPE answers and waits for the caller ID message
    - CPE hangs up on receipt of the caller ID message
    - The phone line rings a second time
    - The CPE answers a second time, connecting the called party with the caller.
    
Timeouts are, obviously, required to ensure this system behaves well when the caller ID message
or the second ring are missing.
*/

enum
{
    ADSI_STANDARD_NONE = 0,
    ADSI_STANDARD_CLASS = 1,
    ADSI_STANDARD_CLIP = 2,
    ADSI_STANDARD_ACLIP = 3,
    ADSI_STANDARD_JCLIP = 4,
    ADSI_STANDARD_CLIP_DTMF = 5,
    ADSI_STANDARD_TDD = 6
};

/* In some of the messages code characters are used, as follows:
        'C' for public callbox
        'L' for long distance
        'O' for overseas
        'P' for private
        'S' for service conflict

    Taiwan and Kuwait change this pattern to:
        'C' for coin/public callbox
        'I' for international call
        'O' for out of area call
        'P' for private
 */

/*! Definitions for CLASS (Custom Local Area Signaling Services) */
enum
{
    /*! Single data message caller ID */
    CLASS_SDMF_CALLERID =               0x04,
    /*! Multiple data message caller ID */
    CLASS_MDMF_CALLERID =               0x80,
    /*! Single data message message waiting */
    CLASS_SDMF_MSG_WAITING =            0x06,
    /*! Multiple data message message waiting */
    CLASS_MDMF_MSG_WAITING =            0x82
};

/*! CLASS MDMF message IDs */
enum
{
    /*! Date and time (MMDDHHMM) */
    MCLASS_DATETIME =                   0x01,
    /*! Caller number */
    MCLASS_CALLER_NUMBER =              0x02,
    /*! Dialed number */
    MCLASS_DIALED_NUMBER =              0x03,
    /*! Caller number absent: 'O' or 'P' */
    MCLASS_ABSENCE1 =                   0x04,
    /*! Call forward: universal ('0'), on busy ('1'), or on unanswered ('2') */
    MCLASS_REDIRECT =                   0x05,
    /*! Long distance: 'L' */
    MCLASS_QUALIFIER =                  0x06,
    /*! Caller's name */
    MCLASS_CALLER_NAME =                0x07,
    /*! Caller's name absent: 'O' or 'P' */
    MCLASS_ABSENCE2 =                   0x08,
    /*! Alternate route */
    MCLASS_ALT_ROUTE =                  0x09
};

/*! CLASS MDMF message waiting message IDs */
/*! Message waiting/not waiting */
#define MCLASS_VISUAL_INDICATOR         0x0B

/*! Definitions for CLIP (Calling Line Identity Presentation) (from ETS 300 659-1) */
enum
{
    /*! Multiple data message caller ID */
    CLIP_MDMF_CALLERID =                0x80,
    /*! Multiple data message message waiting */
    CLIP_MDMF_MSG_WAITING =             0x82,
    /*! Multiple data message charge information */
    CLIP_MDMF_CHARGE_INFO =             0x86,
    /*! Multiple data message SMS */
    CLIP_MDMF_SMS =                     0x89
};

/*! CLIP message IDs (from ETS 300 659-1) */
enum
{
    /*! Date and time (MMDDHHMM) */
    CLIP_DATETIME =                     0x01,
    /*! Caller number (AKA calling line identity) */
    CLIP_CALLER_NUMBER =                0x02,
    /*! Dialed number (AKA called line identity) */
    CLIP_DIALED_NUMBER =                0x03,
    /*! Caller number absent: 'O' or 'P' (AKA reason for absence of calling line identity) */
    CLIP_ABSENCE1 =                     0x04,
    /*! Caller's name (AKA calling party name) */
    CLIP_CALLER_NAME =                  0x07,
    /*! Caller's name absent: 'O' or 'P' (AKA reason for absence of calling party name) */
    CLIP_ABSENCE2 =                     0x08,
    /*! Visual indicator */
    CLIP_VISUAL_INDICATOR =             0x0B,
    /*! Message ID */
    CLIP_MESSAGE_ID =                   0x0D,
    /*! Complementary calling line identity */
    CLIP_COMPLEMENTARY_CALLER_NUMBER =  0x10,
    /*! Call type - voice call (1), ring-back-when-free call (2), calling name delivery (3) or msg waiting call(0x81) */
    CLIP_CALLTYPE =                     0x11,
    /*! Number of messages */
    CLIP_NUM_MSG =                      0x13,
    /*! Type of forwarded call */
    CLIP_TYPE_OF_FORWARDED_CALL =       0x15,
    /*! Type of calling user */
    CLIP_TYPE_OF_CALLING_USER =         0x16,
    /*! Redirecting number */
    CLIP_REDIR_NUMBER =                 0x1A,
    /*! Charge */
    CLIP_CHARGE =                       0x20,
    /*! Duration of the call */
    CLIP_DURATION =                     0x23,
    /*! Additional charge */
    CLIP_ADD_CHARGE =                   0x21,
    /*! Display information */
    CLIP_DISPLAY_INFO =                 0x50,
    /*! Service information */
    CLIP_SERVICE_INFO =                 0x55
};

/*! Definitions for A-CLIP (Analog Calling Line Identity Presentation) */
enum
{
    /*! Single data message caller ID frame */
    ACLIP_SDMF_CALLERID =               0x04,
    /*! Multiple data message caller ID frame */
    ACLIP_MDMF_CALLERID =               0x80
};

/*! A-CLIP MDM message IDs */
enum
{
    /*! Date and time (MMDDHHMM) */
    ACLIP_DATETIME =                    0x01,
    /*! Caller number */
    ACLIP_CALLER_NUMBER =               0x02,
    /*! Dialed number */
    ACLIP_DIALED_NUMBER =               0x03,
    /*! Caller number absent: 'O' or 'P' */
    ACLIP_NUMBER_ABSENCE =              0x04,
    /*! Call forward: universal, on busy, or on unanswered */
    ACLIP_REDIRECT =                    0x05,
    /*! Long distance call: 'L' */
    ACLIP_QUALIFIER =                   0x06,
    /*! Caller's name */
    ACLIP_CALLER_NAME =                 0x07,
    /*! Caller's name absent: 'O' or 'P' */
    ACLIP_NAME_ABSENCE =                0x08
};

/*! Definitions for J-CLIP (Japan Calling Line Identity Presentation) */
/*! Multiple data message caller ID frame */
#define JCLIP_MDMF_CALLERID             0x40

/*! J-CLIP MDM message IDs */
enum
{
    /*! Caller number */
    JCLIP_CALLER_NUMBER =               0x02,
    /*! Caller number data extension signal */
    JCLIP_CALLER_NUM_DES =              0x21,
    /*! Dialed number */
    JCLIP_DIALED_NUMBER =               0x09,
    /*! Dialed number data extension signal */
    JCLIP_DIALED_NUM_DES =              0x22,
    /*! Caller number absent: 'C', 'O', 'P' or 'S' */
    JCLIP_ABSENCE =                     0x04
};

/* Definitions for CLIP-DTMF and its variants */

/*! Caller number is '#' terminated DTMF. */
#define CLIP_DTMF_HASH_TERMINATED       '#'
/*! Caller number is 'C' terminated DTMF. */
#define CLIP_DTMF_C_TERMINATED          'C'

/*! Caller number */
#define CLIP_DTMF_HASH_CALLER_NUMBER    'A'
/*! Caller number absent: private (1), overseas (2) or not available (3) */
#define CLIP_DTMF_HASH_ABSENCE          'D'
/*! Caller ID field with no explicit field type */
#define CLIP_DTMF_HASH_UNSPECIFIED      0

/*! Caller number */
#define CLIP_DTMF_C_CALLER_NUMBER       'A'
/*! Diverting number */
#define CLIP_DTMF_C_REDIRECT_NUMBER     'D'
/*! Caller number absent: private/restricted (00) or not available (10) */
#define CLIP_DTMF_C_ABSENCE             'B'

/*!
    ADSI transmitter descriptor. This contains all the state information for an ADSI
    (caller ID, CLASS, CLIP, ACLIP) transmit channel.
 */
typedef struct adsi_tx_state_s adsi_tx_state_t;

/*!
    ADSI receiver descriptor. This contains all the state information for an ADSI
    (caller ID, CLASS, CLIP, ACLIP, JCLIP) receive channel.
 */
typedef struct adsi_rx_state_s adsi_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Initialise an ADSI receive context.
    \param s The ADSI receive context.
    \param standard The code for the ADSI standard to be used.
    \param put_msg A callback routine called to deliver the received messages
           to the application.
    \param user_data An opaque pointer for the callback routine.
    \return A pointer to the initialised context, or NULL if there was a problem.
*/
SPAN_DECLARE(adsi_rx_state_t *) adsi_rx_init(adsi_rx_state_t *s,
                                             int standard,
                                             put_msg_func_t put_msg,
                                             void *user_data);

/*! \brief Release an ADSI receive context.
    \param s The ADSI receive context.
    \return 0 for OK.
*/
SPAN_DECLARE(int) adsi_rx_release(adsi_rx_state_t *s);

/*! \brief Free the resources of an ADSI receive context.
    \param s The ADSI receive context.
    \return 0 for OK.
*/
SPAN_DECLARE(int) adsi_rx_free(adsi_rx_state_t *s);

/*! \brief Receive a chunk of ADSI audio.
    \param s The ADSI receive context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE(int) adsi_rx(adsi_rx_state_t *s, const int16_t amp[], int len);

/*! \brief Initialise an ADSI transmit context.
    \param s The ADSI transmit context.
    \param standard The code for the ADSI standard to be used.
    \return A pointer to the initialised context, or NULL if there was a problem.
*/
SPAN_DECLARE(adsi_tx_state_t *) adsi_tx_init(adsi_tx_state_t *s, int standard);

/*! \brief Release an ADSI transmit context.
    \param s The ADSI transmit context.
    \return 0 for OK.
*/
SPAN_DECLARE(int) adsi_tx_release(adsi_tx_state_t *s);

/*! \brief Free the resources of an ADSI transmit context.
    \param s The ADSI transmit context.
    \return 0 for OK.
*/
SPAN_DECLARE(int) adsi_tx_free(adsi_tx_state_t *s);

/*! \brief Adjust the preamble associated with an ADSI transmit context.
    \param s The ADSI transmit context.
    \param preamble_len The number of bits of preamble.
    \param preamble_ones_len The number of bits of continuous one before a message.
    \param postamble_ones_len The number of bits of continuous one after a message.
    \param stop_bits The number of stop bits per character.
*/
SPAN_DECLARE(void) adsi_tx_set_preamble(adsi_tx_state_t *s,
                                        int preamble_len,
                                        int preamble_ones_len,
                                        int postamble_ones_len,
                                        int stop_bits);

/*! \brief Generate a block of ADSI audio samples.
    \param s The ADSI transmit context.
    \param amp The audio sample buffer.
    \param max_len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE(int) adsi_tx(adsi_tx_state_t *s, int16_t amp[], int max_len);

/*! \brief Request generation of an ADSI alert tone.
    \param s The ADSI transmit context.
*/
SPAN_DECLARE(void) adsi_tx_send_alert_tone(adsi_tx_state_t *s);

/*! \brief Put a message into the input buffer of an ADSI transmit context.
    \param s The ADSI transmit context.
    \param msg The message.
    \param len The length of the message.
    \return The length actually added. If a message is already in progress
            in the transmitter, this function will return zero, as it will
            not successfully add the message to the buffer. If the message is
            invalid (e.g. it is too long), this function will return -1.
*/
SPAN_DECLARE(int) adsi_tx_put_message(adsi_tx_state_t *s, const uint8_t *msg, int len);

/*! \brief Get a field from an ADSI message.
    \param s The ADSI receive context.
    \param msg The message buffer.
    \param msg_len The length of the message.
    \param pos Current position within the message. Set to -1 when starting a message.
    \param field_type The type code for the field.
    \param field_body Pointer to the body of the field.
    \param field_len The length of the field, or -1 for no more fields, or -2 for message structure corrupt.
*/
SPAN_DECLARE(int) adsi_next_field(adsi_rx_state_t *s, const uint8_t *msg, int msg_len, int pos, uint8_t *field_type, uint8_t const **field_body, int *field_len);

/*! \brief Insert the header or a field into an ADSI message.
    \param s The ADSI transmit context.
    \param msg The message buffer.
    \param len The current length of the message.
    \param field_type The type code for the new field.
    \param field_body Pointer to the body of the new field.
    \param field_len The length of the new field.
*/
SPAN_DECLARE(int) adsi_add_field(adsi_tx_state_t *s, uint8_t *msg, int len, uint8_t field_type, uint8_t const *field_body, int field_len);

/*! \brief Return a short name for an ADSI standard
    \param standard The code for the standard.
    \return A pointer to the name.
*/
SPAN_DECLARE(const char *) adsi_standard_to_str(int standard);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
