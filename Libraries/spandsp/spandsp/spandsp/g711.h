/*
 * SpanDSP - a series of DSP components for telephony
 *
 * g711.h - In line A-law and u-law conversion routines
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2001 Steve Underwood
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
 * $Id: g711.h,v 1.19 2009/04/12 09:12:10 steveu Exp $
 */

/*! \file */

/*! \page g711_page A-law and mu-law handling
Lookup tables for A-law and u-law look attractive, until you consider the impact
on the CPU cache. If it causes a substantial area of your processor cache to get
hit too often, cache sloshing will severely slow things down. The main reason
these routines are slow in C, is the lack of direct access to the CPU's "find
the first 1" instruction. A little in-line assembler fixes that, and the
conversion routines can be faster than lookup tables, in most real world usage.
A "find the first 1" instruction is available on most modern CPUs, and is a
much underused feature. 

If an assembly language method of bit searching is not available, these routines
revert to a method that can be a little slow, so the cache thrashing might not
seem so bad :(

Feel free to submit patches to add fast "find the first 1" support for your own
favourite processor.

Look up tables are used for transcoding between A-law and u-law, since it is
difficult to achieve the precise transcoding procedure laid down in the G.711
specification by other means.
*/

#if !defined(_SPANDSP_G711_H_)
#define _SPANDSP_G711_H_

/* The usual values to use on idle channels, to emulate silence */
/*! Idle value for A-law channels */
#define G711_ALAW_IDLE_OCTET        0x5D
/*! Idle value for u-law channels */
#define G711_ULAW_IDLE_OCTET        0xFF

enum
{
    G711_ALAW = 0,
    G711_ULAW
};

/*!
    G.711 state
 */
typedef struct g711_state_s g711_state_t;

#if defined(__cplusplus)
extern "C"
{
#endif

/* N.B. It is tempting to use look-up tables for A-law and u-law conversion.
 *      However, you should consider the cache footprint.
 *
 *      A 64K byte table for linear to x-law and a 512 byte table for x-law to
 *      linear sound like peanuts these days, and shouldn't an array lookup be
 *      real fast? No! When the cache sloshes as badly as this one will, a tight
 *      calculation may be better. The messiest part is normally finding the
 *      segment, but a little inline assembly can fix that on an i386, x86_64 and
 *      many other modern processors.
 */
 
/*
 * Mu-law is basically as follows:
 *
 *      Biased Linear Input Code        Compressed Code
 *      ------------------------        ---------------
 *      00000001wxyza                   000wxyz
 *      0000001wxyzab                   001wxyz
 *      000001wxyzabc                   010wxyz
 *      00001wxyzabcd                   011wxyz
 *      0001wxyzabcde                   100wxyz
 *      001wxyzabcdef                   101wxyz
 *      01wxyzabcdefg                   110wxyz
 *      1wxyzabcdefgh                   111wxyz
 *
 * Each biased linear code has a leading 1 which identifies the segment
 * number. The value of the segment number is equal to 7 minus the number
 * of leading 0's. The quantization interval is directly available as the
 * four bits wxyz.  * The trailing bits (a - h) are ignored.
 *
 * Ordinarily the complement of the resulting code word is used for
 * transmission, and so the code word is complemented before it is returned.
 *
 * For further information see John C. Bellamy's Digital Telephony, 1982,
 * John Wiley & Sons, pps 98-111 and 472-476.
 */

/* Enable the trap as per the MIL-STD */
//#define ULAW_ZEROTRAP
/*! Bias for u-law encoding from linear. */
#define ULAW_BIAS        0x84

/*! \brief Encode a linear sample to u-law
    \param linear The sample to encode.
    \return The u-law value.
*/
static __inline__ uint8_t linear_to_ulaw(int linear)
{
    uint8_t u_val;
    int mask;
    int seg;

    /* Get the sign and the magnitude of the value. */
    if (linear >= 0)
    {
        linear = ULAW_BIAS + linear;
        mask = 0xFF;
    }
    else
    {
        linear = ULAW_BIAS - linear;
        mask = 0x7F;
    }

    seg = top_bit(linear | 0xFF) - 7;

    /*
     * Combine the sign, segment, quantization bits,
     * and complement the code word.
     */
    if (seg >= 8)
        u_val = (uint8_t) (0x7F ^ mask);
    else
        u_val = (uint8_t) (((seg << 4) | ((linear >> (seg + 3)) & 0xF)) ^ mask);
#ifdef ULAW_ZEROTRAP
    /* Optional ITU trap */
    if (u_val == 0)
        u_val = 0x02;
#endif
    return  u_val;
}
/*- End of function --------------------------------------------------------*/

/*! \brief Decode an u-law sample to a linear value.
    \param ulaw The u-law sample to decode.
    \return The linear value.
*/
static __inline__ int16_t ulaw_to_linear(uint8_t ulaw)
{
    int t;
    
    /* Complement to obtain normal u-law value. */
    ulaw = ~ulaw;
    /*
     * Extract and bias the quantization bits. Then
     * shift up by the segment number and subtract out the bias.
     */
    t = (((ulaw & 0x0F) << 3) + ULAW_BIAS) << (((int) ulaw & 0x70) >> 4);
    return  (int16_t) ((ulaw & 0x80)  ?  (ULAW_BIAS - t)  :  (t - ULAW_BIAS));
}
/*- End of function --------------------------------------------------------*/

/*
 * A-law is basically as follows:
 *
 *      Linear Input Code        Compressed Code
 *      -----------------        ---------------
 *      0000000wxyza             000wxyz
 *      0000001wxyza             001wxyz
 *      000001wxyzab             010wxyz
 *      00001wxyzabc             011wxyz
 *      0001wxyzabcd             100wxyz
 *      001wxyzabcde             101wxyz
 *      01wxyzabcdef             110wxyz
 *      1wxyzabcdefg             111wxyz
 *
 * For further information see John C. Bellamy's Digital Telephony, 1982,
 * John Wiley & Sons, pps 98-111 and 472-476.
 */

/*! The A-law alternate mark inversion mask */
#define ALAW_AMI_MASK       0x55

/*! \brief Encode a linear sample to A-law
    \param linear The sample to encode.
    \return The A-law value.
*/
static __inline__ uint8_t linear_to_alaw(int linear)
{
    int mask;
    int seg;
    
    if (linear >= 0)
    {
        /* Sign (bit 7) bit = 1 */
        mask = ALAW_AMI_MASK | 0x80;
    }
    else
    {
        /* Sign (bit 7) bit = 0 */
        mask = ALAW_AMI_MASK;
        linear = -linear - 1;
    }

    /* Convert the scaled magnitude to segment number. */
    seg = top_bit(linear | 0xFF) - 7;
    if (seg >= 8)
    {
        if (linear >= 0)
        {
            /* Out of range. Return maximum value. */
            return (uint8_t) (0x7F ^ mask);
        }
        /* We must be just a tiny step below zero */
        return (uint8_t) (0x00 ^ mask);
    }
    /* Combine the sign, segment, and quantization bits. */
    return (uint8_t) (((seg << 4) | ((linear >> ((seg)  ?  (seg + 3)  :  4)) & 0x0F)) ^ mask);
}
/*- End of function --------------------------------------------------------*/

/*! \brief Decode an A-law sample to a linear value.
    \param alaw The A-law sample to decode.
    \return The linear value.
*/
static __inline__ int16_t alaw_to_linear(uint8_t alaw)
{
    int i;
    int seg;

    alaw ^= ALAW_AMI_MASK;
    i = ((alaw & 0x0F) << 4);
    seg = (((int) alaw & 0x70) >> 4);
    if (seg)
        i = (i + 0x108) << (seg - 1);
    else
        i += 8;
    return (int16_t) ((alaw & 0x80)  ?  i  :  -i);
}
/*- End of function --------------------------------------------------------*/

/*! \brief Transcode from A-law to u-law, using the procedure defined in G.711.
    \param alaw The A-law sample to transcode.
    \return The best matching u-law value.
*/
SPAN_DECLARE(uint8_t) alaw_to_ulaw(uint8_t alaw);

/*! \brief Transcode from u-law to A-law, using the procedure defined in G.711.
    \param ulaw The u-law sample to transcode.
    \return The best matching A-law value.
*/
SPAN_DECLARE(uint8_t) ulaw_to_alaw(uint8_t ulaw);

/*! \brief Decode from u-law or A-law to linear.
    \param s The G.711 context.
    \param amp The linear audio buffer.
    \param g711_data The G.711 data.
    \param g711_bytes The number of G.711 samples to decode.
    \return The number of samples of linear audio produced.
*/
SPAN_DECLARE(int) g711_decode(g711_state_t *s,
                              int16_t amp[],
                              const uint8_t g711_data[],
                              int g711_bytes);

/*! \brief Encode from linear to u-law or A-law.
    \param s The G.711 context.
    \param g711_data The G.711 data.
    \param amp The linear audio buffer.
    \param len The number of samples to encode.
    \return The number of G.711 samples produced.
*/
SPAN_DECLARE(int) g711_encode(g711_state_t *s,
                              uint8_t g711_data[],
                              const int16_t amp[],
                              int len);

/*! \brief Transcode between u-law and A-law.
    \param s The G.711 context.
    \param g711_out The resulting G.711 data.
    \param g711_in The original G.711 data.
    \param g711_bytes The number of G.711 samples to transcode.
    \return The number of G.711 samples produced.
*/
SPAN_DECLARE(int) g711_transcode(g711_state_t *s,
                                 uint8_t g711_out[],
                                 const uint8_t g711_in[],
                                 int g711_bytes);

/*! Initialise a G.711 encode or decode context.
    \param s The G.711 context.
    \param mode The G.711 mode.
    \return A pointer to the G.711 context, or NULL for error. */
SPAN_DECLARE(g711_state_t *) g711_init(g711_state_t *s, int mode);

/*! Release a G.711 encode or decode context.
    \param s The G.711 context.
    \return 0 for OK. */
SPAN_DECLARE(int) g711_release(g711_state_t *s);

/*! Free a G.711 encode or decode context.
    \param s The G.711 context.
    \return 0 for OK. */
SPAN_DECLARE(int) g711_free(g711_state_t *s);

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
