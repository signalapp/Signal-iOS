/*
 * SpanDSP - a series of DSP components for telephony
 *
 * v17rx.h - ITU V.17 modem receive part
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
 * $Id: v17rx.h,v 1.65 2009/07/09 13:52:09 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_V17RX_H_)
#define _SPANDSP_V17RX_H_

/*! \page v17rx_page The V.17 receiver
\section v17rx_page_sec_1 What does it do?
The V.17 receiver implements the receive side of a V.17 modem. This can operate
at data rates of 14400, 12000, 9600 and 7200 bits/second. The audio input is a stream
of 16 bit samples, at 8000 samples/second. The transmit and receive side of V.17
modems operate independantly. V.17 is mostly used for FAX transmission over PSTN
lines, where it provides the standard 14400 bits/second rate. 

\section v17rx_page_sec_2 How does it work?
V.17 uses QAM modulation, at 2400 baud, and trellis coding. Constellations with
16, 32, 64, and 128 points are defined. After one bit per baud is absorbed by the
trellis coding, this gives usable bit rates of 7200, 9600, 12000, and 14400 per
second.

V.17 specifies a training sequence at the start of transmission, which makes the
design of a V.17 receiver relatively straightforward. The first stage of the
training sequence consists of 256
symbols, alternating between two constellation positions. The receiver monitors
the signal power, to sense the possible presence of a valid carrier. When the
alternating signal begins, the power rising above a minimum threshold (-43dBm0)
causes the main receiver computation to begin. The initial measured power is
used to quickly set the gain of the receiver. After this initial settling, the
front end gain is locked, and the adaptive equalizer tracks any subsequent
signal level variation. The signal is oversampled to 24000 samples/second (i.e.
signal, zero, zero, signal, zero, zero, ...) and fed to a complex root raised
cosine pulse shaping filter. This filter has been modified from the conventional
root raised cosine filter, by shifting it up the band, to be centred at the nominal
carrier frequency. This filter interpolates the samples, pulse shapes, and performs
a fractional sample delay at the same time. 192 sets of filter coefficients are used
to achieve a set of finely spaces fractional sample delays, between zero and
one sample. By choosing every fifth sample, and the appropriate set of filter
coefficients, the properly tuned symbol tracker can select data samples at 4800
samples/second from points within 0.28 degrees of the centre and mid-points of
each symbol. The output of the filter is multiplied by a complex carrier, generated
by a DDS. The result is a baseband signal, requiring no further filtering, apart from
an adaptive equalizer. The baseband signal is fed to a T/2 adaptive equalizer.
A band edge component maximisation algorithm is used to tune the sampling, so the samples
fed to the equalizer are close to the mid point and edges of each symbol. Initially
the algorithm is very lightly damped, to ensure the symbol alignment pulls in
quickly. Because the sampling rate will not be precisely the same as the
transmitter's (the spec. says the symbol timing should be within 0.01%), the
receiver constantly evaluates and corrects this sampling throughout its
operation. During the symbol timing maintainence phase, the algorithm uses
a heavier damping.

The carrier is specified as 1800Hz +- 1Hz at the transmitter, and 1800 +-7Hz at
the receiver. The receive carrier would only be this inaccurate if the link
includes FDM sections. These are being phased out, but the design must still
allow for the worst case. Using an initial 1800Hz signal for demodulation gives
a worst case rotation rate for the constellation of about one degree per symbol.
Once the symbol timing synchronisation algorithm has been given time to lock to the
symbol timing of the initial alternating pattern, the phase of the demodulated signal
is recorded on two successive symbols - once for each of the constellation positions.
The receiver then tracks the symbol alternations, until a large phase jump occurs.
This signifies the start of the next phase of the training sequence. At this
point the total phase shift between the original recorded symbol phase, and the
symbol phase just before the phase jump occurred is used to provide a coarse
estimation of the rotation rate of the constellation, and it current absolute
angle of rotation. These are used to update the current carrier phase and phase
update rate in the carrier DDS. The working data already in the pulse shaping
filter and equalizer buffers is given a similar step rotation to pull it all
into line. From this point on, a heavily damped integrate and dump approach,
based on the angular difference between each received constellation position and
its expected position, is sufficient to track the carrier, and maintain phase
alignment. A fast rough approximator for the arc-tangent function is adequate
for the estimation of the angular error. 

The next phase of the training sequence is a scrambled sequence of two
particular symbols. We train the T/2 adaptive equalizer using this sequence. The
scrambling makes the signal sufficiently diverse to ensure the equalizer
converges to the proper generalised solution. At the end of this sequence, the
equalizer should be sufficiently well adapted that is can correctly resolve the
full QAM constellation. However, the equalizer continues to adapt throughout
operation of the modem, fine tuning on the more complex data patterns of the
full QAM constellation. 

In the last phase of the training sequence, the modem enters normal data
operation, with a short defined period of all ones as data. As in most high
speed modems, data in a V.17 modem passes through a scrambler, to whiten the
spectrum of the signal. The transmitter should initialise its data scrambler,
and pass the ones through it. At the end of the ones, real data begins to pass
through the scrambler, and the transmit modem is in normal operation. The
receiver tests that ones are really received, in order to verify the modem
trained correctly. If all is well, the data following the ones is fed to the
application, and the receive modem is up and running. Unfortunately, some
transmit side of some real V.17 modems fail to initialise their scrambler before
sending the ones. This means the first 23 received bits (the length of the
scrambler register) cannot be trusted for the test. The receive modem,
therefore, only tests that bits starting at bit 24 are really ones.

The V.17 signal is trellis coded. Two bits of each symbol are convolutionally coded
to form a 3 bit trellis code - the two original bits, plus an extra redundant bit. It
is possible to ignore the trellis coding, and just decode the non-redundant bits.
However, the noise performance of the receiver would suffer. Using a proper
trellis decoder adds several dB to the noise tolerance to the receiving modem. Trellis
coding seems quite complex at first sight, but is fairly straightforward once you
get to grips with it.

Trellis decoding tracks the data in terms of the possible states of the convolutional
coder at the transmitter. There are 8 possible states of the V.17 coder. The first
step in trellis decoding is to find the best candidate constellation point
for each of these 8 states. One of thse will be our final answer. The constellation
has been designed so groups of 8 are spread fairly evenly across it. Locating them
is achieved is a reasonably fast manner, by looking up the answers in a set of space
map tables. The disadvantage is the tables are potentially large enough to affect
cache performance. The trellis decoder works over 16 successive symbols. The result
of decoding is not known until 16 symbols after the data enters the decoder. The
minimum total accumulated mismatch between each received point and the actual
constellation (termed the distance) is assessed for each of the 8 states. A little
analysis of the coder shows that each of the 8 current states could be arrived at
from 4 different previous states, through 4 different constellation bit patterns.
For each new state, the running total distance is arrived at by inspecting a previous
total plus a new distance for the appropriate 4 previous states. The minimum of the 4
values becomes the new distance for the state. Clearly, a mechanism is needed to stop
this distance from growing indefinitely. A sliding window, and several other schemes
are possible. However, a simple single pole IIR is very simple, and provides adequate
results.

For each new state we store the constellation bit pattern, or path, to that state, and
the number of the previous state. We find the minimum distance amongst the 8 new
states for each new symbol. We then trace back through the states, until we reach the
one 16 states ago which leads to the current minimum distance. The bit pattern stored
there is the error corrected bit pattern for that symbol.

So, what does Trellis coding actually achieve? TCM is easier to understand by looking
at the V.23bis modem spec. The V.32bis spec. is very similar to V.17, except that it
is a full duplex modem and has non-TCM options, as well as the TCM ones in V.17.

V32bis defines two options for pumping 9600 bits per second down a phone line - one
with and one without TCM. Both run at 2400 baud. The non-TCM one uses simple 16 point
QAM on the raw data. The other takes two out of every four raw bits, and convolutionally
encodes them to 3. Now we have 5 bits per symbol, and we need 32 point QAM to send the
data.

The raw error rate from simple decoding of the 32 point QAM is horrible compared to
decoding the 16 point QAM. If a point decoded from the 32 point QAM is wrong, the likely
correct choice should be one of the adjacent ones. It is unlikely to have been one that
is far away across the constellation, unless there was a huge noise spike, interference,
or something equally nasty. Now, the 32 point symbols do not exist in isolation. There
was a kind of temporal smearing in the convolutional coding. It created a well defined
dependency between successive symbols. If we knew for sure what the last few symbols
were, they would lead us to a limited group of possible values for the current symbol,
constrained by the behaviour of the convolutional coder. If you look at how the symbols
were mapped to constellation points, you will see the mapping tries to spread those
possible symbols as far apart as possible. This will leave only one that is pretty
close to the received point, which must be the correct choice. However, this assumes
we know the last few symbols for sure. Since we don't, we have a bit more work to do
to achieve reliable decoding.

Instead of decoding to the nearest point on the constellation, we decode to a group of
likely constellation points in the neighbourhood of the received point. We record the
mismatch for each - that is the distance across the constellation between the received
point and the group of nearby points. To avoid square roots, recording x2 + y2 can be
good enough. Symbol by symbol, we record this information. After a few symbols we can
stand back and look at the recorded information.

For each symbol we have a set of possible symbol values and error metric pairs. The
dependency between symbols, created by the convolutional coder, means some paths from
symbol to symbol are possible and some are not. It we trace back through the possible
symbol to symbol paths, and total up the error metric through those paths, we end up
with a set of figures of merit (or more accurately figures of demerit, since
larger == worse) for the likelihood of each path being the correct one. The path with
the lowest total metric is the most likely, and gives us our final choice for what we
think the current symbol really is.

That was hard work. It takes considerable computation to do this selection and traceback,
symbol by symbol. We need to get quite a lot from this. It needs to drive the error rate
down so far that is compensates for the much higher error rate due to the larger
constellation, and then buys us some actual benefit. Well in the example we are looking
at - V.32bis at 9600bps - it works out the error rate from the TCM option is like using
the non-TCM option with several dB more signal to noise ratio. That's nice. The non-TCM
option is pretty reasonable on most phone lines, but a better error rate is always a
good thing. However, V32bis includes a 14,400bps option. That uses 2400 baud, and 6 bit
symbols. Convolutional encoding increases that to 7 bits per symbol, by taking 2 bits and
encoding them to 3. This give a 128 point QAM constellation. Again, the difference between
using this, and using just an uncoded 64 point constellation is equivalent to maybe 5dB of
extra signal to noise ratio. However, in this case it is the difference between the modem
working only on the most optimal lines, and being widely usable across most phone lines.
TCM absolutely transformed the phone line modem business.
*/

/*!
    V.17 modem receive side descriptor. This defines the working state for a
    single instance of a V.17 modem receiver.
*/
typedef struct v17_rx_state_s v17_rx_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/*! Initialise a V.17 modem receive context.
    \brief Initialise a V.17 modem receive context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 7200, 9600, 12000 and 14400.
    \param put_bit The callback routine used to put the received data.
    \param user_data An opaque pointer passed to the put_bit routine.
    \return A pointer to the modem context, or NULL if there was a problem. */
SPAN_DECLARE(v17_rx_state_t *) v17_rx_init(v17_rx_state_t *s, int bit_rate, put_bit_func_t put_bit, void *user_data);

/*! Reinitialise an existing V.17 modem receive context.
    \brief Reinitialise an existing V.17 modem receive context.
    \param s The modem context.
    \param bit_rate The bit rate of the modem. Valid values are 7200, 9600, 12000 and 14400.
    \param short_train TRUE if a short training sequence is expected.
    \return 0 for OK, -1 for bad parameter */
SPAN_DECLARE(int) v17_rx_restart(v17_rx_state_t *s, int bit_rate, int short_train);

/*! Release a V.17 modem receive context.
    \brief Release a V.17 modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v17_rx_release(v17_rx_state_t *s);

/*! Free a V.17 modem receive context.
    \brief Free a V.17 modem receive context.
    \param s The modem context.
    \return 0 for OK */
SPAN_DECLARE(int) v17_rx_free(v17_rx_state_t *s);

/*! Get the logging context associated with a V.17 modem receive context.
    \brief Get the logging context associated with a V.17 modem receive context.
    \param s The modem context.
    \return A pointer to the logging context */
SPAN_DECLARE(logging_state_t *) v17_rx_get_logging_state(v17_rx_state_t *s);

/*! Change the put_bit function associated with a V.17 modem receive context.
    \brief Change the put_bit function associated with a V.17 modem receive context.
    \param s The modem context.
    \param put_bit The callback routine used to handle received bits.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v17_rx_set_put_bit(v17_rx_state_t *s, put_bit_func_t put_bit, void *user_data);

/*! Change the modem status report function associated with a V.17 modem receive context.
    \brief Change the modem status report function associated with a V.17 modem receive context.
    \param s The modem context.
    \param handler The callback routine used to report modem status changes.
    \param user_data An opaque pointer. */
SPAN_DECLARE(void) v17_rx_set_modem_status_handler(v17_rx_state_t *s, modem_rx_status_func_t handler, void *user_data);

/*! Process a block of received V.17 modem audio samples.
    \brief Process a block of received V.17 modem audio samples.
    \param s The modem context.
    \param amp The audio sample buffer.
    \param len The number of samples in the buffer.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE_NONSTD(int) v17_rx(v17_rx_state_t *s, const int16_t amp[], int len);

/*! Fake processing of a missing block of received V.17 modem audio samples.
    (e.g due to packet loss).
    \brief Fake processing of a missing block of received V.17 modem audio samples.
    \param s The modem context.
    \param len The number of samples to fake.
    \return The number of samples unprocessed.
*/
SPAN_DECLARE(int) v17_rx_fillin(v17_rx_state_t *s, int len);

/*! Get a snapshot of the current equalizer coefficients.
    \brief Get a snapshot of the current equalizer coefficients.
    \param s The modem context.
    \param coeffs The vector of complex coefficients.
    \return The number of coefficients in the vector. */
#if defined(SPANDSP_USE_FIXED_POINTx)
SPAN_DECLARE(int) v17_rx_equalizer_state(v17_rx_state_t *s, complexi_t **coeffs);
#else
SPAN_DECLARE(int) v17_rx_equalizer_state(v17_rx_state_t *s, complexf_t **coeffs);
#endif

/*! Get the current received carrier frequency.
    \param s The modem context.
    \return The frequency, in Hertz. */
SPAN_DECLARE(float) v17_rx_carrier_frequency(v17_rx_state_t *s);

/*! Get the current symbol timing correction since startup.
    \param s The modem context.
    \return The correction. */
SPAN_DECLARE(float) v17_rx_symbol_timing_correction(v17_rx_state_t *s);

/*! Get a current received signal power.
    \param s The modem context.
    \return The signal power, in dBm0. */
SPAN_DECLARE(float) v17_rx_signal_power(v17_rx_state_t *s);

/*! Set the power level at which the carrier detection will cut in
    \param s The modem context.
    \param cutoff The signal cutoff power, in dBm0. */
SPAN_DECLARE(void) v17_rx_signal_cutoff(v17_rx_state_t *s, float cutoff);

/*! Set a handler routine to process QAM status reports
    \param s The modem context.
    \param handler The handler routine.
    \param user_data An opaque pointer passed to the handler routine. */
SPAN_DECLARE(void) v17_rx_set_qam_report_handler(v17_rx_state_t *s, qam_report_handler_t handler, void *user_data);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
