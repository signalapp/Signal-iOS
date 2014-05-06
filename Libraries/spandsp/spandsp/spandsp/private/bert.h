/*
 * SpanDSP - a series of DSP components for telephony
 *
 * private/bert.h - Bit error rate tests.
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
 * $Id: bert.h,v 1.2 2009/04/14 16:04:54 steveu Exp $
 */

#if !defined(_SPANDSP_PRIVATE_BERT_H_)
#define _SPANDSP_PRIVATE_BERT_H_

typedef struct
{
    uint32_t reg;
    int step;
    int step_bit;
    int bits;
    int zeros;
} bert_tx_state_t;

typedef struct
{
    uint32_t reg;
    uint32_t ref_reg;
    uint32_t master_reg;
    int step;
    int step_bit;
    int resync;
    int bits;
    int zeros;
    int resync_len;
    int resync_percent;
    int resync_bad_bits;
    int resync_cnt;
    int report_countdown;
    int measurement_step;
} bert_rx_state_t;

/*!
    Bit error rate tester (BERT) descriptor. This defines the working state for a
    single instance of the BERT.
*/
struct bert_state_s
{
    int pattern;
    int pattern_class;
    bert_report_func_t reporter;
    void *user_data;
    int report_frequency;
    int limit;

    uint32_t mask;
    int shift;
    int shift2;
    int max_zeros;
    int invert;
    int resync_time;

    int decade_ptr[9];
    int decade_bad[9][10];
    int error_rate;

    bert_tx_state_t tx;
    bert_rx_state_t rx;

    bert_results_t results;

    /*! \brief Error and flow logging control */
    logging_state_t logging;
};

#endif
/*- End of file ------------------------------------------------------------*/
