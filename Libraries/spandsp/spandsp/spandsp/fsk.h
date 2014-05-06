/*
 * SpanDSP - a series of DSP components for telephony
 *
 * fsk.h - FSK modem transmit and receive parts
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
 * $Id: fsk.h,v 1.41 2009/11/02 13:25:20 steveu Exp $
 */

/*! \file */

/*! \page fsk_page FSK modems
\section fsk_page_sec_1 What does it do?
Most of the oldest telephony modems use incoherent FSK modulation. This module can
be used to implement both the transmit and receive sides of a number of these
modems. There are integrated definitions for: 

 - V.21
 - V.23
 - Bell 103
 - Bell 202
 - Weitbrecht (Used for TDD - Telecoms Device for the Deaf)

The audio output or input is a stream of 16 bit samples, at 8000 samples/second.
The transmit and receive sides can be used independantly. 

\section fsk_page_sec_2 The transmitter

The FSK transmitter uses a DDS generator to synthesise the waveform. This
naturally produces phase coherent transitions, as the phase update rate is
switched, producing a clean spectrum. The symbols are not generally an integer
number of samples long. However, the symbol time for the fastest data rate
generally used (1200bps) is more than 7 samples long. The jitter resulting from
switching at the nearest sample is, therefore, acceptable. No interpolation is
used. 

\section fsk_page_sec_3 The receiver

The FSK receiver uses a quadrature correlation technique to demodulate the
signal. Two DDS quadrature oscillators are used. The incoming signal is
correlated with the oscillator signals over a period of one symbol. The
oscillator giving the highest net correlation from its I and Q outputs is the
one that matches the frequency being transmitted during the correlation
interval. Because the transmission is totally asynchronous, the demodulation
process must run sample by sample to find the symbol transitions. The
correlation is performed on a sliding window basis, so the computational load of
demodulating sample by sample is not great. 

Two modes of symbol synchronisation are provided:

    - In synchronous mode, symbol transitions are smoothed, to track their true
      position in the prescence of high timing jitter. This provides the most
      reliable symbol recovery in poor signal to noise conditions. However, it
      takes a little time to settle, so it not really suitable for data streams
      which must start up instantaneously (e.g. the TDD systems used by hearing
      impaired people).

    - In asynchronous mode each transition is taken at face value, with no temporal
      smoothing. There is no settling time for this mode, but when the signal to
      noise ratio is very poor it does not perform as well as the synchronous mode.
*/

#if !defined(_SPANDSP_FSK_H_)
#define _SPANDSP_FSK_H_

/*!
    FSK modem specification. This defines the frequencies, signal levels and
    baud rate (== bit rate for simple FSK) for a single channel of an FSK modem.
*/
typedef struct
{
    /*! Short text name for the modem. */
    const char *name;
    /*! The frequency of the zero bit state, in Hz */
    int freq_zero;
    /*! The frequency of the one bit state, in Hz */
    int freq_one;
    /*! The transmit power level, in dBm0 */
    int tx_level;
    /*! The minimum acceptable receive power level, in dBm0 */
    int min_level;
    /*! The bit rate of the modem, in units of 1/100th bps */
    int baud_rate;
} fsk_spec_t;

/* Predefined FSK modem channels */
enum
{
    FSK_V21CH1 = 0,
    FSK_V21CH2,
    FSK_V23CH1,
    FSK_V23CH2,
    FSK_BELL103CH1,
    FSK_BELL103CH2,
    FSK_BELL202,
    FSK_WEITBRECHT,     /* 45.45 baud version, used for TDD (Telecom Device for the Deaf) */
    FSK_WEITBRECHT50    /* 50 baud version, used for TDD (Telecom Device for the Deaf) */
};

enum
{
    FSK_FRAME_MODE_ASYNC = 0,
    FSK_FRAME_MODE_SYNC = 1,
    FSK_FRAME_MODE_5N1_FRAMES = 7,      /* 5 bits of data + start bit + stop bit */
    FSK_FRAME_MODE_7N1_FRAMES = 9,      /* 7 bits of data + start bit + stop bit */
    FSK_FRAME_MODE_8N1_FRAMES = 10      /* 8 bits of data + start bit + stop bit */
};

SPAN_DECLARE_DATA extern const fsk_spec_t preset_fsk_specs[];

/*!
    FSK modem transmit descriptor. This defines the state of a single working
    instance of an FSK modem transmitter.
*/
typedef struct fsk_tx_state_s fsk_tx_state_t;

/* The longest window will probably be 106 for 75 baud */
#define FSK_MAX_WINDOW_LEN 128

/*!
    FSK modem receive descriptor. This defines the state of a single working
    instance of an FSK modem receiver.
*/
typedef struct fsk_rx_state_s fsk_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise an FSK modem transmit context.
    \brief Initialise an FSK modem transmit context.
    \param s The modem context.
    \param spec The specification of the modem tones and rate.
    \param get_bit The callback routine used to get the data to be transmitted.
    \param user_data An opaque pointer.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(fsk_tx_state_t *) fsk_tx_init(fsk_tx_state_t *s,
                                           const fsk_spec_t *spec,
                                           get_bit_func_t get_bit,
                                           void *user_data);

SPAN_DECLARE(int) fsk_tx_restart(fsk_tx_state_t *s, const fsk_spec_t *spec);
    
SPAN_DECLARE(int) fsk_tx_release(fsk_tx_state_t *s);

SPAN_DECLARE(int) fsk_tx_free(fsk_tx_state_t *s);

/*! Adjust an FSK modem transmit context's power output.
    \brief Adjust an FSK modem transmit context's power output.
    \param s The modem context.
    \param power The power level, in dBm0 */
SPAN_DECLARE(void) fsk_tx_power(fsk_tx_state_t *s, float power);

SPAN_DECLARE(void) fsk_tx_set_get_bit(fsk_tx_state_t *s, get_bit_func_t get_bit, void *user_data);

/*! Change the modem status report function associated with an FSK modem transmit context.
    \brief Change the modem status report function associated with an FSK modem transmit context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) fsk_tx_set_modem_status_handler(fsk_tx_state_t *s, modem_tx_status_func_t handler, void *user_data);

/*! Generate a block of FSK modem audio samples.
    \brief Generate a block of FSK modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples to be generated.
    \return The number of samples actually generated.
*/
SPAN_DECLARE_NONSTD(int) fsk_tx(fsk_tx_state_t *s, int16_t amp[], int len);

/*! Get the current received signal power.
    \param s The modem context.
    \return The signal power, in dBm0. */
SPAN_DECLARE(float) fsk_rx_signal_power(fsk_rx_state_t *s);

/*! Adjust an FSK modem receive context's carrier detect power threshold.
    \brief Adjust an FSK modem receive context's carrier detect power threshold.
    \param s The modem context.
    \param cutoff The power level, in dBm0 */
SPAN_DECLARE(void) fsk_rx_signal_cutoff(fsk_rx_state_t *s, float cutoff);

/*! Initialise an FSK modem receive context.
    \brief Initialise an FSK modem receive context.
    \param s The modem context.
    \param spec The specification of the modem tones and rate.
    \param framing_mode 0 for fully asynchronous mode. 1 for synchronous mode. >1 for
           this many bits per asynchronous character frame.
    \param put_bit The callback routine used to put the received data.
    \param user_data An opaque pointer.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(fsk_rx_state_t *) fsk_rx_init(fsk_rx_state_t *s,
                                           const fsk_spec_t *spec,
                                           int framing_mode,
                                           put_bit_func_t put_bit,
                                           void *user_data);

SPAN_DECLARE(int) fsk_rx_restart(fsk_rx_state_t *s, const fsk_spec_t *spec, int framing_mode);

SPAN_DECLARE(int) fsk_rx_release(fsk_rx_state_t *s);

SPAN_DECLARE(int) fsk_rx_free(fsk_rx_state_t *s);

/*! Process a block of received FSK modem audio samples.
    \brief Process a block of received FSK modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE_NONSTD(int) fsk_rx(fsk_rx_state_t *s, const int16_t *amp, int len);

/*! Fake processing of a missing block of received FSK modem audio samples
    (e.g due to packet loss).
    \brief Fake processing of a missing block of received FSK modem audio samples.
    \param s The modem context.
    \param len The number of samples to fake.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE(int) fsk_rx_fillin(fsk_rx_state_t *s, int len);

SPAN_DECLARE(void) fsk_rx_set_put_bit(fsk_rx_state_t *s, put_bit_func_t put_bit, void *user_data);

/*! Change the modem status report function associated with an FSK modem receive context.
    \brief Change the modem status report function associated with an FSK modem receive context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) fsk_rx_set_modem_status_handler(fsk_rx_state_t *s, modem_rx_status_func_t handler, void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
