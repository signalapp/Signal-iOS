/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t30_api.h - definitions for T.30 fax processing
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
 * $Id: t30_api.h,v 1.10 2009/04/12 09:12:10 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T30_API_H_)
#define _SPANDSP_T30_API_H_

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Set the transmitted NSF frame to be associated with a T.30 context.
    \brief Set the transmitted NSF frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsf A pointer to the frame.
    \param len The length of the frame.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_nsf(t30_state_t *s, const uint8_t *nsf, int len);

/*! Get an NSF frame to be associated with a T.30 context.
    \brief Set an NSF frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsf A pointer to the frame.
    \return the length of the NSF message. */
SPAN_DECLARE(size_t) t30_get_tx_nsf(t30_state_t *s, const uint8_t *nsf[]);

/*! Get an NSF frame to be associated with a T.30 context.
    \brief Set an NSF frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsf A pointer to the frame.
    \return the length of the NSF message. */
SPAN_DECLARE(size_t) t30_get_rx_nsf(t30_state_t *s, const uint8_t *nsf[]);

/*! Set the transmitted NSC frame to be associated with a T.30 context.
    \brief Set the transmitted NSC frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsc A pointer to the frame.
    \param len The length of the frame.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_nsc(t30_state_t *s, const uint8_t *nsc, int len);

/*! Get an NSC frame to be associated with a T.30 context.
    \brief Set an NSC frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsc A pointer to the frame.
    \return the length of the NSC message. */
SPAN_DECLARE(size_t) t30_get_tx_nsc(t30_state_t *s, const uint8_t *nsc[]);

/*! Get an NSC frame to be associated with a T.30 context.
    \brief Set an NSC frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nsc A pointer to the frame.
    \return the length of the NSC message. */
SPAN_DECLARE(size_t) t30_get_rx_nsc(t30_state_t *s, const uint8_t *nsc[]);

/*! Set the transmitted NSS frame to be associated with a T.30 context.
    \brief Set the transmitted NSS frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nss A pointer to the frame.
    \param len The length of the frame.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_nss(t30_state_t *s, const uint8_t *nss, int len);

/*! Get an NSS frame to be associated with a T.30 context.
    \brief Set an NSS frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nss A pointer to the frame.
    \return the length of the NSS message. */
SPAN_DECLARE(size_t) t30_get_tx_nss(t30_state_t *s, const uint8_t *nss[]);

/*! Get an NSS frame to be associated with a T.30 context.
    \brief Set an NSS frame to be associated with a T.30 context.
    \param s The T.30 context.
    \param nss A pointer to the frame.
    \return the length of the NSS message. */
SPAN_DECLARE(size_t) t30_get_rx_nss(t30_state_t *s, const uint8_t *nss[]);

/*! Set the transmitted identifier associated with a T.30 context.
    \brief Set the transmitted identifier associated with a T.30 context.
    \param s The T.30 context.
    \param id A pointer to the identifier.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_ident(t30_state_t *s, const char *id);

/*! Get the transmitted identifier associated with a T.30 context.
    \brief Set the transmitted identifier associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the identifier. */
SPAN_DECLARE(const char *) t30_get_tx_ident(t30_state_t *s);

/*! Get the transmitted identifier associated with a T.30 context.
    \brief Set the transmitted identifier associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the identifier. */
SPAN_DECLARE(const char *) t30_get_rx_ident(t30_state_t *s);

/*! Set the transmitted sub-address associated with a T.30 context.
    \brief Set the transmitted sub-address associated with a T.30 context.
    \param s The T.30 context.
    \param sub_address A pointer to the sub-address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_sub_address(t30_state_t *s, const char *sub_address);

/*! Get the received sub-address associated with a T.30 context.
    \brief Get the received sub-address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the sub-address. */
SPAN_DECLARE(const char *) t30_get_tx_sub_address(t30_state_t *s);

/*! Get the received sub-address associated with a T.30 context.
    \brief Get the received sub-address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the sub-address. */
SPAN_DECLARE(const char *) t30_get_rx_sub_address(t30_state_t *s);

/*! Set the transmitted selective polling address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted selective polling address associated with a T.30 context.
    \param s The T.30 context.
    \param selective_polling_address A pointer to the selective polling address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_selective_polling_address(t30_state_t *s, const char *selective_polling_address);

/*! Get the received selective polling address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received selective polling address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the selective polling address. */
SPAN_DECLARE(const char *) t30_get_tx_selective_polling_address(t30_state_t *s);

/*! Get the received selective polling address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received selective polling address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the selective polling address. */
SPAN_DECLARE(const char *) t30_get_rx_selective_polling_address(t30_state_t *s);

/*! Set the transmitted polled sub-address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted polled sub-address associated with a T.30 context.
    \param s The T.30 context.
    \param polled_sub_address A pointer to the polled sub-address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_polled_sub_address(t30_state_t *s, const char *polled_sub_address);

/*! Get the received polled sub-address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received polled sub-address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the polled sub-address. */
SPAN_DECLARE(const char *) t30_get_tx_polled_sub_address(t30_state_t *s);

/*! Get the received polled sub-address (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received polled sub-address associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the polled sub-address. */
SPAN_DECLARE(const char *) t30_get_rx_polled_sub_address(t30_state_t *s);

/*! Set the transmitted sender ident (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted sender ident associated with a T.30 context.
    \param s The T.30 context.
    \param sender_ident A pointer to the sender ident.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_sender_ident(t30_state_t *s, const char *sender_ident);

/*! Get the received sender ident (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received sender ident associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the sender ident. */
SPAN_DECLARE(const char *) t30_get_tx_sender_ident(t30_state_t *s);

/*! Get the received sender ident (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received sender ident associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the sender ident. */
SPAN_DECLARE(const char *) t30_get_rx_sender_ident(t30_state_t *s);

/*! Set the transmitted password (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted password associated with a T.30 context.
    \param s The T.30 context.
    \param password A pointer to the password.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_password(t30_state_t *s, const char *password);

/*! Get the received password (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received password associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the password. */
SPAN_DECLARE(const char *) t30_get_tx_password(t30_state_t *s);

/*! Get the received password (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received password associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the password. */
SPAN_DECLARE(const char *) t30_get_rx_password(t30_state_t *s);

/*! Set the transmitted ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \param len The length of the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_tsa(t30_state_t *s, int type, const char *address, int len);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_tx_tsa(t30_state_t *s, int *type, const char *address[]);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_rx_tsa(t30_state_t *s, int *type, const char *address[]);

/*! Set the transmitted ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \param len The length of the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_ira(t30_state_t *s, int type, const char *address, int len);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_tx_ira(t30_state_t *s, int *type, const char *address[]);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_rx_ira(t30_state_t *s, int *type, const char *address[]);

/*! Set the transmitted ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \param len The length of the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_cia(t30_state_t *s, int type, const char *address, int len);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_tx_cia(t30_state_t *s, int *type, const char *address[]);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(size_t) t30_get_rx_cia(t30_state_t *s, int *type, const char *address[]);

/*! Set the transmitted ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \param len The length of the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_isp(t30_state_t *s, int type, const char *address, int len);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(size_t) t30_get_tx_isp(t30_state_t *s, int *type, const char *address[]);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(size_t) t30_get_rx_isp(t30_state_t *s, int *type, const char *address[]);

/*! Set the transmitted ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Set the transmitted ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \param len The length of the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_csa(t30_state_t *s, int type, const char *address, int len);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return The length of the address. */
SPAN_DECLARE(size_t) t30_get_tx_csa(t30_state_t *s, int *type, const char *address[]);

/*! Get the received ??? (i.e. the one we will send to the far
    end) associated with a T.30 context.
    \brief Get the received ??? associated with a T.30 context.
    \param s The T.30 context.
    \param type The type of address.
    \param address A pointer to the address.
    \return 0 for OK, else -1. */
SPAN_DECLARE(size_t) t30_get_rx_csa(t30_state_t *s, int *type, const char *address[]);

/*! Set the transmitted header information associated with a T.30 context.
    \brief Set the transmitted header information associated with a T.30 context.
    \param s The T.30 context.
    \param info A pointer to the information string.
    \return 0 for OK, else -1. */
SPAN_DECLARE(int) t30_set_tx_page_header_info(t30_state_t *s, const char *info);

/*! Get the header information associated with a T.30 context.
    \brief Get the header information associated with a T.30 context.
    \param s The T.30 context.
    \param info A pointer to a buffer for the header information.  The buffer
           should be at least 51 bytes long.
    \return the length of the string. */
SPAN_DECLARE(size_t) t30_get_tx_page_header_info(t30_state_t *s, char *info);

/*! Get the country of origin of the remote FAX machine associated with a T.30 context.
    \brief Get the country of origin of the remote FAX machine associated with a T.30 context.
    \param s The T.30 context.
    \return a pointer to the country name, or NULL if the country is not known. */
SPAN_DECLARE(const char *) t30_get_rx_country(t30_state_t *s);

/*! Get the name of the vendor of the remote FAX machine associated with a T.30 context.
    \brief Get the name of the vendor of the remote FAX machine associated with a T.30 context.
    \param s The T.30 context.
    \return a pointer to the vendor name, or NULL if the vendor is not known. */
SPAN_DECLARE(const char *) t30_get_rx_vendor(t30_state_t *s);

/*! Get the name of the model of the remote FAX machine associated with a T.30 context.
    \brief Get the name of the model of the remote FAX machine associated with a T.30 context.
    \param s The T.30 context.
    \return a pointer to the model name, or NULL if the model is not known. */
SPAN_DECLARE(const char *) t30_get_rx_model(t30_state_t *s);

/*! Specify the file name of the next TIFF file to be received by a T.30
    context.
    \brief Set next receive file name.
    \param s The T.30 context.
    \param file The file name
    \param stop_page The maximum page to receive. -1 for no restriction. */
SPAN_DECLARE(void) t30_set_rx_file(t30_state_t *s, const char *file, int stop_page);

/*! Specify the file name of the next TIFF file to be transmitted by a T.30
    context.
    \brief Set next transmit file name.
    \param s The T.30 context.
    \param file The file name
    \param start_page The first page to send. -1 for no restriction.
    \param stop_page The last page to send. -1 for no restriction. */
SPAN_DECLARE(void) t30_set_tx_file(t30_state_t *s, const char *file, int start_page, int stop_page);

/*! Set Internet aware FAX (IAF) mode.
    \brief Set Internet aware FAX (IAF) mode.
    \param s The T.30 context.
    \param iaf TRUE for IAF, or FALSE for non-IAF. */
SPAN_DECLARE(void) t30_set_iaf_mode(t30_state_t *s, int iaf);

/*! Specify if error correction mode (ECM) is allowed by a T.30 context.
    \brief Select ECM capability.
    \param s The T.30 context.
    \param enabled TRUE for ECM capable, FALSE for not ECM capable.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_ecm_capability(t30_state_t *s, int enabled);

/*! Specify the output encoding for TIFF files created during FAX reception.
    \brief Specify the output encoding for TIFF files created during FAX reception.
    \param s The T.30 context.
    \param encoding The coding required. The options are T4_COMPRESSION_ITU_T4_1D,
           T4_COMPRESSION_ITU_T4_2D, T4_COMPRESSION_ITU_T6. T6 is usually the
           densest option, but support for it is broken in a number of software
           packages.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_rx_encoding(t30_state_t *s, int encoding);

/*! Specify the minimum scan line time supported by a T.30 context.
    \brief Specify minimum scan line time.
    \param s The T.30 context.
    \param min_time The minimum permitted scan line time, in milliseconds.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_minimum_scan_line_time(t30_state_t *s, int min_time);

/*! Specify which modem types are supported by a T.30 context.
    \brief Specify supported modems.
    \param s The T.30 context.
    \param supported_modems Bit field list of the supported modems.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_supported_modems(t30_state_t *s, int supported_modems);

/*! Specify which compression types are supported by a T.30 context.
    \brief Specify supported compression types.
    \param s The T.30 context.
    \param supported_compressions Bit field list of the supported compression types.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_supported_compressions(t30_state_t *s, int supported_compressions);

/*! Specify which resolutions are supported by a T.30 context.
    \brief Specify supported resolutions.
    \param s The T.30 context.
    \param supported_resolutions Bit field list of the supported resolutions.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_supported_resolutions(t30_state_t *s, int supported_resolutions);

/*! Specify which images sizes are supported by a T.30 context.
    \brief Specify supported image sizes.
    \param s The T.30 context.
    \param supported_image_sizes Bit field list of the supported widths and lengths.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_supported_image_sizes(t30_state_t *s, int supported_image_sizes);

/*! Specify which special T.30 features are supported by a T.30 context.
    \brief Specify supported T.30 features.
    \param s The T.30 context.
    \param supported_t30_features Bit field list of the supported features.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_supported_t30_features(t30_state_t *s, int supported_t30_features);

/*! Set T.30 status. This may be used to adjust the status from within
    the phase B and phase D callbacks.
    \brief Set T.30 status.
    \param s The T.30 context.
    \param status The new status. */
SPAN_DECLARE(void) t30_set_status(t30_state_t *s, int status);

/*! Specify a period of responding with receiver not ready.
    \brief Specify a period of responding with receiver not ready.
    \param s The T.30 context.
    \param count The number of times to report receiver not ready.
    \return 0 if OK, else -1. */
SPAN_DECLARE(int) t30_set_receiver_not_ready(t30_state_t *s, int count);

/*! Set a callback function for T.30 phase B handling.
    \brief Set a callback function for T.30 phase B handling.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t30_set_phase_b_handler(t30_state_t *s, t30_phase_b_handler_t *handler, void *user_data);

/*! Set a callback function for T.30 phase D handling.
    \brief Set a callback function for T.30 phase D handling.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t30_set_phase_d_handler(t30_state_t *s, t30_phase_d_handler_t *handler, void *user_data);

/*! Set a callback function for T.30 phase E handling.
    \brief Set a callback function for T.30 phase E handling.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t30_set_phase_e_handler(t30_state_t *s, t30_phase_e_handler_t *handler, void *user_data);

/*! Set a callback function for T.30 end of document handling.
    \brief Set a callback function for T.30 end of document handling.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t30_set_document_handler(t30_state_t *s, t30_document_handler_t *handler, void *user_data);

/*! Set a callback function for T.30 frame exchange monitoring. This is called from the heart
    of the signal processing, so don't take too long in the handler routine.
    \brief Set a callback function for T.30 frame exchange monitoring.
    \param s The T.30 context.
    \param handler The callback function.
    \param user_data An opaque pointer passed to the callback function. */
SPAN_DECLARE(void) t30_set_real_time_frame_handler(t30_state_t *s, t30_real_time_frame_handler_t *handler, void *user_data);

/*! Get a pointer to the logging context associated with a T.30 context.
    \brief Get a pointer to the logging context associated with a T.30 context.
    \param s The T.30 context.
    \return A pointer to the logging context, or NULL.
*/
SPAN_DECLARE(logging_state_t *) t30_get_logging_state(t30_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
