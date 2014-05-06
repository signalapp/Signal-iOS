/*
 * SpanDSP - a series of DSP components for telephony
 *
 * at_interpreter.h - AT command interpreter to V.251, V.252, V.253, T.31 and the 3GPP specs.
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2004, 2005, 2006 Steve Underwood
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
 * $Id: at_interpreter.h,v 1.23 2009/02/10 13:06:47 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_AT_INTERPRETER_H_)
#define _SPANDSP_AT_INTERPRETER_H_

/*! \page at_page AT command interpreter
\section at_page_sec_1 What does it do?
The AT interpreter module implements V.251, V.252, V.253, T.31 and various 3GPP
modem control commands.

\section at_page_sec_2 How does it work?
*/

typedef struct at_state_s at_state_t;

typedef int (at_modem_control_handler_t)(at_state_t *s, void *user_data, int op, const char *num);
typedef int (at_tx_handler_t)(at_state_t *s, void *user_data, const uint8_t *buf, size_t len);
typedef int (at_class1_handler_t)(at_state_t *s, void *user_data, int direction, int operation, int val);

enum at_rx_mode_e
{
    AT_MODE_ONHOOK_COMMAND,
    AT_MODE_OFFHOOK_COMMAND,
    AT_MODE_CONNECTED,
    AT_MODE_DELIVERY,
    AT_MODE_HDLC,
    AT_MODE_STUFFED
};

enum at_call_event_e
{
    AT_CALL_EVENT_ALERTING = 1,
    AT_CALL_EVENT_CONNECTED,
    AT_CALL_EVENT_ANSWERED,
    AT_CALL_EVENT_BUSY,
    AT_CALL_EVENT_NO_DIALTONE,
    AT_CALL_EVENT_NO_ANSWER,
    AT_CALL_EVENT_HANGUP
};

enum at_modem_control_operation_e
{
    /*! Start an outgoing call. */
    AT_MODEM_CONTROL_CALL,
    /*! Answer an incoming call. */
    AT_MODEM_CONTROL_ANSWER,
    /*! Hangup a call. */
    AT_MODEM_CONTROL_HANGUP,
    /*! Take the line off hook. */
    AT_MODEM_CONTROL_OFFHOOK,
    /*! Put the line on hook. */
    AT_MODEM_CONTROL_ONHOOK,
    /*! Control V.24 Circuit 108, "data terminal ready". */
    AT_MODEM_CONTROL_DTR,
    /*! Control V.24 Circuit 105, "request to send". */
    AT_MODEM_CONTROL_RTS,
    /*! Control V.24 Circuit 106, "clear to send". */
    AT_MODEM_CONTROL_CTS,
    /*! Control V.24 Circuit 109, "receive line signal detector" (i.e. carrier detect). */
    AT_MODEM_CONTROL_CAR,
    /*! Control V.24 Circuit 125, "ring indicator". */
    AT_MODEM_CONTROL_RNG,
    /*! Control V.24 Circuit 107, "data set ready". */
    AT_MODEM_CONTROL_DSR,
    /*! Set the caller ID for outgoing calls. */
    AT_MODEM_CONTROL_SETID,
    /* The remainder of the control functions should not get past the modem, to the
       application. */
    AT_MODEM_CONTROL_RESTART,
    AT_MODEM_CONTROL_DTE_TIMEOUT
};

enum
{
    AT_RESPONSE_CODE_OK = 0,
    AT_RESPONSE_CODE_CONNECT,
    AT_RESPONSE_CODE_RING,
    AT_RESPONSE_CODE_NO_CARRIER,
    AT_RESPONSE_CODE_ERROR,
    AT_RESPONSE_CODE_XXX,
    AT_RESPONSE_CODE_NO_DIALTONE,
    AT_RESPONSE_CODE_BUSY,
    AT_RESPONSE_CODE_NO_ANSWER,
    AT_RESPONSE_CODE_FCERROR,
    AT_RESPONSE_CODE_FRH3
};

/*!
    AT profile.
*/
typedef struct
{
    /*! TRUE if character echo is enabled */
    int echo;
    /*! TRUE if verbose reporting is enabled */
    int verbose;
    /*! TRUE if result codes are verbose */
    int result_code_format;
    /*! TRUE if pulse dialling is the default */
    int pulse_dial;
    /*! ??? */
    int double_escape;
    /*! ??? */
    int adaptive_receive;
    /*! The state of all possible S registers */
    uint8_t s_regs[100];
} at_profile_t;

#if defined(__cplusplus)
extern "C"
{
#endif

SPAN_DECLARE(void) at_set_at_rx_mode(at_state_t *s, int new_mode);

SPAN_DECLARE(void) at_put_response(at_state_t *s, const char *t);

SPAN_DECLARE(void) at_put_numeric_response(at_state_t *s, int val);

SPAN_DECLARE(void) at_put_response_code(at_state_t *s, int code);

SPAN_DECLARE(void) at_reset_call_info(at_state_t *s);

/*! Set the call information for an AT interpreter.
    \brief Set the call information for an AT interpreter.
    \param s The AT interpreter context.
    \param id .
    \param value . */
SPAN_DECLARE(void) at_set_call_info(at_state_t *s, char const *id, char const *value);

SPAN_DECLARE(void) at_display_call_info(at_state_t *s);

SPAN_DECLARE(int) at_modem_control(at_state_t *s, int op, const char *num);

SPAN_DECLARE(void) at_call_event(at_state_t *s, int event);

SPAN_DECLARE(void) at_interpreter(at_state_t *s, const char *cmd, int len);

SPAN_DECLARE(void) at_set_class1_handler(at_state_t *s, at_class1_handler_t handler, void *user_data);

/*! Initialise an AT interpreter context.
    \brief Initialise an AT interpreter context.
    \param s The AT context.
    \param at_tx_handler x.
    \param at_tx_user_data x.
    \param modem_control_handler x.
    \param modem_control_user_data x.
    \return A pointer to the AT context, or NULL if there was a problem. */
SPAN_DECLARE(at_state_t *) at_init(at_state_t *s,
                                   at_tx_handler_t *at_tx_handler,
                                   void *at_tx_user_data,
                                   at_modem_control_handler_t *modem_control_handler,
                                   void *modem_control_user_data);

/*! Release an AT interpreter context.
    \brief Release an AT interpreter context.
    \param s The AT context.
    \return 0 for OK */
SPAN_DECLARE(int) at_release(at_state_t *s);

/*! Free an AT interpreter context.
    \brief Free an AT interpreter context.
    \param s The AT context.
    \return 0 for OK */
SPAN_DECLARE(int) at_free(at_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
