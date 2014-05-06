/*
 * SpanDSP - a series of DSP components for telephony
 *
 * t30_fcf.h - ITU T.30 fax control field definitions
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
 * $Id: t30_fcf.h,v 1.18 2009/10/08 15:14:31 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_T30_FCF_H_)
#define _SPANDSP_T30_FCF_H_

enum
{
    /*! Initial identification messages */
    /*! From the called to the calling terminal. */
    T30_DIS = 0x80,         /*! [0000 0001] Digital identification signal */
    T30_CSI = 0x40,         /*! [0000 0010] Called subscriber identification */
    T30_NSF = 0x20,         /*! [0000 0100] Non-standard facilities */

    /*! Commands to send */
    /*! From a calling terminal wishing to be a receiver, to a called terminal
        which is capable of transmitting. */
    T30_DTC = 0x81,         /*! [1000 0001] Digital transmit command */
    T30_CIG = 0x41,         /*! [1000 0010] Calling subscriber identification */
    T30_NSC = 0x21,         /*! [1000 0100] Non-standard facilities command */
    T30_PWD = 0xC1,         /*! [1000 0011] Password */
    T30_SEP = 0xA1,         /*! [1000 0101] Selective polling */
    T30_PSA = 0x61,         /*! [1000 0110] Polled subaddress */
    T30_CIA = 0xE1,         /*! [1000 0111] Calling subscriber internet address */
    T30_ISP = 0x11,         /*! [1000 1000] Internet selective polling address */

    /*! Commands to receive */
    /*! From a calling terminal wishing to be a transmitter, to a called terminal
        which is capable of receiving. */
    T30_DCS = 0x82,         /*! [X100 0001] Digital command signal */
    T30_TSI = 0x42,         /*! [X100 0010] Transmitting subscriber information */
    T30_NSS = 0x22,         /*! [X100 0100] Non-standard facilities set-up */
    T30_SUB = 0xC2,         /*! [X100 0011] Sub-address */
    T30_SID = 0xA2,         /*! [X100 0101] Sender identification */
    /*! T30_TCF - Training check is a burst of 1.5s of zeros sent using the image modem */
    T30_CTC = 0x12,         /*! [X100 1000] Continue to correct */
    T30_TSA = 0x62,         /*! [X100 0110] Transmitting subscriber internet address */
    T30_IRA = 0xE2,         /*! [X100 0111] Internet routing address */

    /*! Pre-message response signals */
    /*! From the receiver to the transmitter. */
    T30_CFR = 0x84,         /*! [X010 0001] Confirmation to receive */
    T30_FTT = 0x44,         /*! [X010 0010] Failure to train */
    T30_CTR = 0xC4,         /*! [X010 0011] Response for continue to correct */
    T30_CSA = 0x24,         /*! [X010 0100] Called subscriber internet address */

    /*! Post-message commands */
    T30_EOM = 0x8E,         /*! [X111 0001] End of message */
    T30_MPS = 0x4E,         /*! [X111 0010] Multipage signal */
    T30_EOP = 0x2E,         /*! [X111 0100] End of procedure */
    T30_PRI_EOM = 0x9E,     /*! [X111 1001] Procedure interrupt - end of procedure */
    T30_PRI_MPS = 0x5E,     /*! [X111 1010] Procedure interrupt - multipage signal */
    T30_PRI_EOP = 0x3E,     /*! [X111 1100] Procedure interrupt - end of procedure */
    T30_EOS = 0x1E,         /*! [X111 1000] End of selection */
    T30_PPS = 0xBE,         /*! [X111 1101] Partial page signal */
    T30_EOR = 0xCE,         /*! [X111 0011] End of retransmission */
    T30_RR = 0x6E,          /*! [X111 0110] Receiver ready */

    /*! Post-message responses */
    T30_MCF = 0x8C,         /*! [X011 0001] Message confirmation */
    T30_RTP = 0xCC,         /*! [X011 0011] Retrain positive */
    T30_RTN = 0x4C,         /*! [X011 0010] Retrain negative */
    T30_PIP = 0xAC,         /*! [X011 0101] Procedure interrupt positive */
    T30_PIN = 0x2C,         /*! [X011 0100] Procedure interrupt negative */
    T30_PPR = 0xBC,         /*! [X011 1101] Partial page request */
    T30_RNR = 0xEC,         /*! [X011 0111] Receive not ready */
    T30_ERR = 0x1C,         /*! [X011 1000] Response for end of retransmission */
    T30_FDM = 0xFC,         /*! [X011 1111] File diagnostics message */

    /*! Other line control signals */
    T30_DCN = 0xFA,         /*! [X101 1111] Disconnect */
    T30_CRP = 0x1A,         /*! [X101 1000] Command repeat */
    T30_FNV = 0xCA,         /*! [X101 0011] Field not valid */
    T30_TNR = 0xEA,         /*! [X101 0111] Transmitter not ready */
    T30_TR = 0x6A,          /*! [X101 0110] Transmitter ready */
    T30_TK = 0x4B,          /*! [1101 0010] Transmitter keys */
    T30_RK = 0x4A,          /*! [0101 0010] Receiver keys */
    T30_PSS = 0x1F,         /*! [1111 1000] Present signature signal (used only as FCF2) */
    T30_DES = 0xA0,         /*! [0000 0101] Digital extended signal */
    T30_DEC = 0x93,         /*! [1100 1001] Digital extended command */
    T30_DER = 0x53,         /*! [1100 1010] Digital extended request */
    T30_DTR = 0x11,         /*! [1000 1000] Digital turnaround request (conflicts with ISP) */
    T30_DNK = 0x9A,         /*! [X101 1001] Digital not acknowledge */
    T30_PID = 0x6C,         /*! [X011 0110] Procedure interrupt disconnect */
    T30_SPI = 0x10,         /*! [0000 1000] Security page indicator */
    T30_SPT = 0x80,         /*! [0000 0001] Security page type */

    /*! Something only use as a secondary value in error correcting mode */
    T30_NULL = 0x00,        /*! [0000 0000] Nothing to say */

    /*! Information frame types used for error correction mode, in T.4 */
    T4_FCD = 0x06,          /*! [0110 0000] Facsimile coded data */
    T4_RCP = 0x86           /*! [0110 0001] Return to control for partial page */
};

#endif
/*- End of file ------------------------------------------------------------*/
