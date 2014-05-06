/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t38_non_ecm_buffer.h - A rate adapting buffer for T.38 non-ECM image
 *                        and TCF data
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2005, 2006, 2007, 2008 Steve Underwood
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
 * $Id: t38_non_ecm_buffer.h,v 1.7.4.1 2009/12/19 06:43:28 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T38_NON_ECM_BUFFER_H_)
#define _SPANDSP_T38_NON_ECM_BUFFER_H_

/*! \page t38_non_ecm_buffer_page T.38 rate adapting non-ECM image data buffer
\section t38_non_ecm_buffer_page_sec_1 What does it do?

The T.38 rate adapting non-ECM image data buffer is used to buffer TCF and non-ECM
FAX image data being gatewayed from a T.38 link to an analogue FAX modem link.

As well as rate adapting, the buffer has the ability to impose a minimum on the number
of bits per row of image data. This allows any row padding zeros to be stripped from
the data stream, to minimise the data sent as T.38 packets, and be reinserted before
the data is sent to its final destination. Not all T.38 implementations support this
feature, so it's use must be negotiated.

\section t38_non_ecm_buffer_page_sec_2 How does it work?

When inserting padding bits, whether to ensure a minimum row time or for flow control,
it is important the right value is inserted at the right point in the data sequence.
If we are in the optional initial period of all ones, we can insert a byte of extra
ones at any time. Once we pass that initial stage, TCF and image data need separate
handling.

TCF data is all zeros. Once the period of all zeros has begun it is OK to insert
additional bytes of zeros at any point.

Image data consists of rows, separated by EOL (end of line) markers. Inserting
zeros at arbitrary times would corrupt the image. However, it is OK to insert a
considerable number of extra zeros just before an EOL. Therefore we track where the
EOL markers occur as we fill the buffer. As we empty the buffer stop outputting real
data, and start outputting bytes of zero, if we reach this last EOL marker location.
The EOL marker is 11 zeros following by 1 (1D mode) or 2 (2D mode) ones. Therefore, it
always spills across 2 bytes in the buffer, and there is always a point where we can
insert our extra zeros between bytes.

Padding between the group of successive EOL markers which for the RTC (return to control)
marker that ends an image causes some FAX machines not to recognise them as an RTC condition.
Therefore, our padding applies special protection so padding never occurs between two
successive EOL markers, with no pixel data between them.
*/

/*! The buffer length much be a power of two. The chosen length is big enough for
    over 9s of data at the V.17 14,400bps rate. */    
#define T38_NON_ECM_TX_BUF_LEN  16384

/*! \brief A flow controlled non-ECM image data buffer, for buffering T.38 to analogue
           modem data.
*/
typedef struct t38_non_ecm_buffer_state_s t38_non_ecm_buffer_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Initialise a T.38 rate adapting non-ECM buffer context.
    \param s The buffer context.
    \param mode TRUE for image data mode, or FALSE for TCF mode.
    \param bits The minimum number of bits per FAX image row.
    \return A pointer to the buffer context, or NULL if there was a problem. */
SPAN_DECLARE(t38_non_ecm_buffer_state_t *) t38_non_ecm_buffer_init(t38_non_ecm_buffer_state_t *s, int mode, int min_row_bits);

SPAN_DECLARE(int) t38_non_ecm_buffer_release(t38_non_ecm_buffer_state_t *s);

SPAN_DECLARE(int) t38_non_ecm_buffer_free(t38_non_ecm_buffer_state_t *s);

/*! \brief Set the mode of a T.38 rate adapting non-ECM buffer context.
    \param s The buffer context.
    \param mode TRUE for image data mode, or FALSE for TCF mode.
    \param bits The minimum number of bits per FAX image row. */
SPAN_DECLARE(void) t38_non_ecm_buffer_set_mode(t38_non_ecm_buffer_state_t *s, int mode, int min_row_bits);

/*! \brief Inject data to T.38 rate adapting non-ECM buffer context.
    \param s The buffer context.
    \param buf The data buffer to be injected.
    \param len The length of the data to be injected. */
SPAN_DECLARE(void) t38_non_ecm_buffer_inject(t38_non_ecm_buffer_state_t *s, const uint8_t *buf, int len);

/*! \brief Inform a T.38 rate adapting non-ECM buffer context that the incoming data has finished,
           and the contents of the buffer should be played out as quickly as possible.
    \param s The buffer context. */
SPAN_DECLARE(void) t38_non_ecm_buffer_push(t38_non_ecm_buffer_state_t *s);

/*! \brief Report the input status of a T.38 rate adapting non-ECM buffer context to the specified
           logging context.
    \param s The buffer context.
    \param logging The logging context. */
SPAN_DECLARE(void) t38_non_ecm_buffer_report_input_status(t38_non_ecm_buffer_state_t *s, logging_state_t *logging);

/*! \brief Report the output status of a T.38 rate adapting non-ECM buffer context to the specified
           logging context.
    \param s The buffer context.
    \param logging The logging context. */
SPAN_DECLARE(void) t38_non_ecm_buffer_report_output_status(t38_non_ecm_buffer_state_t *s, logging_state_t *logging);

/*! \brief Get the next bit of data from a T.38 rate adapting non-ECM buffer context.
    \param user_data The buffer context, cast to a void pointer.
    \return The next bit, or one of the values indicating a change of modem status. */
SPAN_DECLARE_NONSTD(int) t38_non_ecm_buffer_get_bit(void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
