/*
 * SpanDSP - a series of DSP components for telephony
 *
 * fax_modems.h - definitions for the analogue modem set for fax processing
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2008 Steve Underwood
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
 * $Id: fax_modems.h,v 1.11 2009/04/26 12:55:23 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_FAX_MODEMS_H_)
#define _SPANDSP_FAX_MODEMS_H_

enum
{
    FAX_MODEM_NONE = -1,
    FAX_MODEM_FLUSH = 0,
    FAX_MODEM_SILENCE_TX,
    FAX_MODEM_SILENCE_RX,
    FAX_MODEM_CED_TONE,
    FAX_MODEM_CNG_TONE,
    FAX_MODEM_NOCNG_TONE,
    FAX_MODEM_V21_TX,
    FAX_MODEM_V17_TX,
    FAX_MODEM_V27TER_TX,
    FAX_MODEM_V29_TX,
    FAX_MODEM_V21_RX,
    FAX_MODEM_V17_RX,
    FAX_MODEM_V27TER_RX,
    FAX_MODEM_V29_RX
};

/*!
    The set of modems needed for FAX, plus the auxilliary stuff, like tone generation.
*/
typedef struct fax_modems_state_s fax_modems_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/* N.B. the following are currently a work in progress */
SPAN_DECLARE(int) fax_modems_v17_v21_rx(void *user_data, const int16_t amp[], int len);
SPAN_DECLARE(int) fax_modems_v27ter_v21_rx(void *user_data, const int16_t amp[], int len);
SPAN_DECLARE(int) fax_modems_v29_v21_rx(void *user_data, const int16_t amp[], int len);
SPAN_DECLARE(int) fax_modems_v17_v21_rx_fillin(void *user_data, int len);
SPAN_DECLARE(int) fax_modems_v27ter_v21_rx_fillin(void *user_data, int len);
SPAN_DECLARE(int) fax_modems_v29_v21_rx_fillin(void *user_data, int len);
SPAN_DECLARE(void) fax_modems_start_rx_modem(fax_modems_state_t *s, int which);

SPAN_DECLARE(void) fax_modems_set_tep_mode(fax_modems_state_t *s, int use_tep);

SPAN_DECLARE(fax_modems_state_t *) fax_modems_init(fax_modems_state_t *s,
                                                   int use_tep,
                                                   hdlc_frame_handler_t hdlc_accept,
                                                   hdlc_underflow_handler_t hdlc_tx_underflow,
                                                   put_bit_func_t non_ecm_put_bit,
                                                   get_bit_func_t non_ecm_get_bit,
                                                   tone_report_func_t tone_callback,
                                                   void *user_data);

SPAN_DECLARE(int) fax_modems_release(fax_modems_state_t *s);

SPAN_DECLARE(int) fax_modems_free(fax_modems_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
