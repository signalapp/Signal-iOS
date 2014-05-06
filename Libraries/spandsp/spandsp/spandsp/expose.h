/*
 * SpanDSP - a series of DSP components for telephony
 *
 * expose.h - Expose the internal structures of spandsp, for users who
 *            really need that.
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
 * $Id: expose.h,v 1.14.4.1 2009/12/19 09:47:56 steveu Exp $
 */

/*! \file */

/* TRY TO ONLY INCLUDE THIS IF YOU REALLY REALLY HAVE TO */

#if !defined(_SPANDSP_EXPOSE_H_)
#define _SPANDSP_EXPOSE_H_

#include <spandsp/private/logging.h>
#include <spandsp/private/schedule.h>
#include <spandsp/private/bitstream.h>
#include <spandsp/private/queue.h>
#include <spandsp/private/awgn.h>
#include <spandsp/private/noise.h>
#include <spandsp/private/bert.h>
#include <spandsp/private/tone_generate.h>
#include <spandsp/private/bell_r2_mf.h>
#include <spandsp/private/sig_tone.h>
#include <spandsp/private/dtmf.h>
#include <spandsp/private/g711.h>
#include <spandsp/private/g722.h>
#include <spandsp/private/g726.h>
#include <spandsp/private/lpc10.h>
#include <spandsp/private/gsm0610.h>
#include <spandsp/private/oki_adpcm.h>
#include <spandsp/private/ima_adpcm.h>
#include <spandsp/private/hdlc.h>
#include <spandsp/private/time_scale.h>
#include <spandsp/private/super_tone_tx.h>
#include <spandsp/private/super_tone_rx.h>
#include <spandsp/private/silence_gen.h>
#include <spandsp/private/swept_tone.h>
#include <spandsp/private/echo.h>
#include <spandsp/private/modem_echo.h>
#include <spandsp/private/async.h>
#include <spandsp/private/fsk.h>
#include <spandsp/private/v29rx.h>
#include <spandsp/private/v29tx.h>
#include <spandsp/private/v17rx.h>
#include <spandsp/private/v17tx.h>
#include <spandsp/private/v22bis.h>
#include <spandsp/private/v27ter_rx.h>
#include <spandsp/private/v27ter_tx.h>
#include <spandsp/private/modem_connect_tones.h>
#include <spandsp/private/at_interpreter.h>
#include <spandsp/private/fax_modems.h>
#include <spandsp/private/t4_rx.h>
#include <spandsp/private/t4_tx.h>
#include <spandsp/private/t30.h>
#include <spandsp/private/fax.h>
#include <spandsp/private/t38_core.h>
#include <spandsp/private/t38_non_ecm_buffer.h>
#include <spandsp/private/t38_gateway.h>
#include <spandsp/private/t38_terminal.h>
#include <spandsp/private/t31.h>
#include <spandsp/private/v8.h>
#include <spandsp/private/v18.h>
#include <spandsp/private/v42.h>
#include <spandsp/private/v42bis.h>
#include <spandsp/private/adsi.h>

#endif
/*- End of file ------------------------------------------------------------*/
