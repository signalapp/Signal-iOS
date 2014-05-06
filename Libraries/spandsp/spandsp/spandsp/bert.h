/*
 * SpanDSP - a series of DSP components for telephony
 *
 * bert.h - Bit error rate tests.
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
 * $Id: bert.h,v 1.23 2009/02/10 13:06:47 steveu Exp $
 */

#if !defined(_SPANDSP_BERT_H_)
#define _SPANDSP_BERT_H_

/*! \page bert_page The Bit Error Rate tester
\section bert_page_sec_1 What does it do?
The Bit Error Rate tester generates a pseudo random bit stream. It also accepts such
a pattern, synchronises to it, and checks the bit error rate in this stream.

\section bert_page_sec_2 How does it work?
The Bit Error Rate tester generates a bit stream, with a repeating 2047 bit pseudo
random pattern, using an 11 stage polynomial generator. It also accepts such a pattern,
synchronises to it, and checks the bit error rate in this stream. If the error rate is
excessive the tester assumes synchronisation has been lost, and it attempts to
resynchronise with the stream.

The bit error rate is continuously assessed against decadic ranges -
    > 1 in 10^2
    > 1 in 10^3
    > 1 in 10^4
    > 1 in 10^5
    > 1 in 10^6
    > 1 in 10^7
    < 1 in 10^7
To ensure fairly smooth results from this assessment, each decadic level is assessed
over 10/error rate bits. That is, to assess if the signal's BER is above or below 1 in 10^5
the software looks over 10*10^5 => 10^6 bits.
*/

enum
{
    BERT_REPORT_SYNCED = 0,
    BERT_REPORT_UNSYNCED,
    BERT_REPORT_REGULAR,
    BERT_REPORT_GT_10_2,
    BERT_REPORT_LT_10_2,
    BERT_REPORT_LT_10_3,
    BERT_REPORT_LT_10_4,
    BERT_REPORT_LT_10_5,
    BERT_REPORT_LT_10_6,
    BERT_REPORT_LT_10_7
};

/* The QBF strings should be:
    "VoyeZ Le BricK GeanT QuE J'ExaminE PreS Du WharF 123 456 7890 + - * : = $ % ( )"
    "ThE QuicK BrowN FoX JumpS OveR ThE LazY DoG 123 456 7890 + - * : = $ % ( )"
*/

enum
{
    BERT_PATTERN_ZEROS = 0,
    BERT_PATTERN_ONES,
    BERT_PATTERN_7_TO_1,
    BERT_PATTERN_3_TO_1,
    BERT_PATTERN_1_TO_1,
    BERT_PATTERN_1_TO_3,
    BERT_PATTERN_1_TO_7,
    BERT_PATTERN_QBF,
    BERT_PATTERN_ITU_O151_23,
    BERT_PATTERN_ITU_O151_20,
    BERT_PATTERN_ITU_O151_15,
    BERT_PATTERN_ITU_O152_11,
    BERT_PATTERN_ITU_O153_9
};

/*!
    Bit error rate tester (BERT) results descriptor. This is used to report the
    results of a BER test.
*/
typedef struct
{
    int total_bits;
    int bad_bits;
    int resyncs;
} bert_results_t;

typedef void (*bert_report_func_t)(void *user_data, int reason, bert_results_t *bert_results);

/*!
    Bit error rate tester (BERT) descriptor. This defines the working state for a
    single instance of the BERT.
*/
typedef struct bert_state_s bert_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Return a short description of a BERT event.
    \param event The event type.
    \return A pointer to a short text string describing the event. */
SPAN_DECLARE(const char *) bert_event_to_str(int event);

/*! Initialise a BERT context.
    \param s The BERT context.
    \param limit The maximum test duration.
    \param pattern One of the supported BERT signal patterns.
    \param resync_len ???
    \param resync_percent The percentage of bad bits which will cause a resync.
    \return The BERT context. */
SPAN_DECLARE(bert_state_t *) bert_init(bert_state_t *s, int limit, int pattern, int resync_len, int resync_percent);

SPAN_DECLARE(int) bert_release(bert_state_t *s);

SPAN_DECLARE(int) bert_free(bert_state_t *s);

/*! Get the next bit of the BERT sequence from the generator.
    \param s The BERT context.
    \return The bit. */
SPAN_DECLARE(int) bert_get_bit(bert_state_t *s);

/*! Put the next bit of the BERT sequence to the analyser.
    \param s The BERT context.
    \param bit The bit. */
SPAN_DECLARE(void) bert_put_bit(bert_state_t *s, int bit);

/*! Set the callback function for reporting the test status.
    \param s The BERT context.
    \param freq The required frequency of regular reports.
    \param reporter The callback function.
    \param user_data An opaque pointer passed to the reporter routine. */
SPAN_DECLARE(void) bert_set_report(bert_state_t *s, int freq, bert_report_func_t reporter, void *user_data);

/*! Get the results of the BERT.
    \param s The BERT context.
    \param results The results.
    \return The size of the result structure. */
SPAN_DECLARE(int) bert_result(bert_state_t *s, bert_results_t *results);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
