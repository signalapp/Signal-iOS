/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t4_tx.h - definitions for T.4 FAX transmit processing
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
 * $Id: t4_tx.h,v 1.2.2.3 2009/12/21 17:18:40 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T4_TX_H_)
#define _SPANDSP_T4_TX_H_

typedef int (*t4_row_read_handler_t)(void *user_data, uint8_t buf[], size_t len);

#if defined(__cplusplus)
extern "C" {
#endif

/*! \brief Prepare for transmission of a document.
    \param s The T.4 context.
    \param file The name of the file to be sent.
    \param start_page The first page to send. -1 for no restriction.
    \param stop_page The last page to send. -1 for no restriction.
    \return A pointer to the context, or NULL if there was a problem. */
SPAN_DECLARE(t4_state_t *) t4_tx_init(t4_state_t *s, const char *file, int start_page, int stop_page);

/*! \brief Prepare to send the next page of the current document.
    \param s The T.4 context.
    \return zero for success, -1 for failure. */
SPAN_DECLARE(int) t4_tx_start_page(t4_state_t *s);

/*! \brief Prepare the current page for a resend.
    \param s The T.4 context.
    \return zero for success, -1 for failure. */
SPAN_DECLARE(int) t4_tx_restart_page(t4_state_t *s);

/*! \brief Check for the existance of the next page, and whether its format is like the
    current one. This information can be needed before it is determined that the current
    page is finished with.
    \param s The T.4 context.
    \return 0 for next page found with the same format as the current page.
            1 for next page found with different format from the current page.
            -1 for no page found, or file failure. */
SPAN_DECLARE(int) t4_tx_next_page_has_different_format(t4_state_t *s);

/*! \brief Complete the sending of a page.
    \param s The T.4 context.
    \return zero for success, -1 for failure. */
SPAN_DECLARE(int) t4_tx_end_page(t4_state_t *s);

/*! \brief Return the next bit of the current document page, without actually
           moving forward in the buffer. The document will be padded for the
           current minimum scan line time.
    \param s The T.4 context.
    \return The next bit (i.e. 0 or 1). For the last bit of data, bit 1 is
            set (i.e. the returned value is 2 or 3). */
SPAN_DECLARE(int) t4_tx_check_bit(t4_state_t *s);

/*! \brief Get the next bit of the current document page. The document will
           be padded for the current minimum scan line time.
    \param s The T.4 context.
    \return The next bit (i.e. 0 or 1). For the last bit of data, bit 1 is
            set (i.e. the returned value is 2 or 3). */
SPAN_DECLARE(int) t4_tx_get_bit(t4_state_t *s);

/*! \brief Get the next byte of the current document page. The document will
           be padded for the current minimum scan line time.
    \param s The T.4 context.
    \return The next byte. For the last byte of data, bit 8 is
            set. In this case, one or more bits of the byte may be padded with
            zeros, to complete the byte. */
SPAN_DECLARE(int) t4_tx_get_byte(t4_state_t *s);

/*! \brief Get the next chunk of the current document page. The document will
           be padded for the current minimum scan line time.
    \param s The T.4 context.
    \param buf The buffer into which the chunk is to written.
    \param max_len The maximum length of the chunk.
    \return The actual length of the chunk. If this is less than max_len it 
            indicates that the end of the document has been reached. */
SPAN_DECLARE(int) t4_tx_get_chunk(t4_state_t *s, uint8_t buf[], int max_len);

/*! \brief End the transmission of a document. Tidy up and close the file.
           This should be used to end T.4 transmission started with t4_tx_init.
    \param s The T.4 context.
    \return 0 for success, otherwise -1. */
SPAN_DECLARE(int) t4_tx_release(t4_state_t *s);

/*! \brief End the transmission of a document. Tidy up, close the file and
           free the context. This should be used to end T.4 transmission
           started with t4_tx_init.
    \param s The T.4 context.
    \return 0 for success, otherwise -1. */
SPAN_DECLARE(int) t4_tx_free(t4_state_t *s);

/*! \brief Set the encoding for the encoded data.
    \param s The T.4 context.
    \param encoding The encoding. */
SPAN_DECLARE(void) t4_tx_set_tx_encoding(t4_state_t *s, int encoding);

/*! \brief Set the minimum number of encoded bits per row. This allows the
           makes the encoding process to be set to comply with the minimum row
           time specified by a remote receiving machine.
    \param s The T.4 context.
    \param bits The minimum number of bits per row. */
SPAN_DECLARE(void) t4_tx_set_min_row_bits(t4_state_t *s, int bits);

/*! \brief Set the identity of the local machine, for inclusion in page headers.
    \param s The T.4 context.
    \param ident The identity string. */
SPAN_DECLARE(void) t4_tx_set_local_ident(t4_state_t *s, const char *ident);

/*! Set the info field, included in the header line included in each page of an encoded
    FAX. This is a string of up to 50 characters. Other information (date, local ident, etc.)
    are automatically included in the header. If the header info is set to NULL or a zero
    length string, no header lines will be added to the encoded FAX.
    \brief Set the header info.
    \param s The T.4 context.
    \param info A string, of up to 50 bytes, which will form the info field. */
SPAN_DECLARE(void) t4_tx_set_header_info(t4_state_t *s, const char *info);

/*! \brief Set the row read handler for a T.4 transmit context.
    \param s The T.4 transmit context.
    \param handler A pointer to the handler routine.
    \param user_data An opaque pointer passed to the handler routine.
    \return 0 for success, otherwise -1. */
SPAN_DECLARE(int) t4_tx_set_row_read_handler(t4_state_t *s, t4_row_read_handler_t handler, void *user_data);

/*! \brief Get the row-to-row (y) resolution of the current page.
    \param s The T.4 context.
    \return The resolution, in pixels per metre. */
SPAN_DECLARE(int) t4_tx_get_y_resolution(t4_state_t *s);

/*! \brief Get the column-to-column (x) resolution of the current page.
    \param s The T.4 context.
    \return The resolution, in pixels per metre. */
SPAN_DECLARE(int) t4_tx_get_x_resolution(t4_state_t *s);

/*! \brief Get the width of the current page, in pixel columns.
    \param s The T.4 context.
    \return The number of columns. */
SPAN_DECLARE(int) t4_tx_get_image_width(t4_state_t *s);

/*! \brief Get the number of pages in the file.
    \param s The T.4 context.
    \return The number of pages, or -1 if there is an error. */
SPAN_DECLARE(int) t4_tx_get_pages_in_file(t4_state_t *s);

/*! \brief Get the currnet page number in the file.
    \param s The T.4 context.
    \return The page number, or -1 if there is an error. */
SPAN_DECLARE(int) t4_tx_get_current_page_in_file(t4_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
