/*
 * SpanDSP - a series of DSP components for telephony
 *
 * bit_operations.h - Various bit level operations, such as bit reversal
 *
 * Written by Steve Underwood <steveu@coppice.org>
 *
 * Copyright (C) 2006 Steve Underwood
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
 * $Id: bit_operations.h,v 1.27 2009/07/10 13:15:56 steveu Exp $
 */

/*! \file */

#if !defined(_SPANDSP_BIT_OPERATIONS_H_)
#define _SPANDSP_BIT_OPERATIONS_H_

#if defined(__i386__)  ||  defined(__x86_64__)
#if !defined(__SUNPRO_C)  ||  (__SUNPRO_C >= 0x0590)
#define SPANDSP_USE_86_ASM
#endif
#endif

#if defined(__cplusplus)
extern "C"
{
#endif

/*! \brief Find the bit position of the highest set bit in a word
    \param bits The word to be searched
    \return The bit number of the highest set bit, or -1 if the word is zero. */
static __inline__ int top_bit(unsigned int bits)
{
#if defined(SPANDSP_USE_86_ASM)
    int res;

    __asm__ (" xorl %[res],%[res];\n"
             " decl %[res];\n"
             " bsrl %[bits],%[res]\n"
             : [res] "=&r" (res)
             : [bits] "rm" (bits));
    return res;
#elif defined(__ppc__)  ||   defined(__powerpc__)
    int res;

    __asm__ ("cntlzw %[res],%[bits];\n"
             : [res] "=&r" (res)
             : [bits] "r" (bits));
    return 31 - res;
#elif defined(_M_IX86)
    /* Visual Studio i386 */
    __asm
    {
        xor eax, eax
        dec eax
        bsr eax, bits
    }
#elif defined(_M_X64)
    /* Visual Studio x86_64 */
    /* TODO: Need the appropriate x86_64 code */
    int res;

    if (bits == 0)
        return -1;
    res = 0;
    if (bits & 0xFFFF0000)
    {
        bits &= 0xFFFF0000;
        res += 16;
    }
    if (bits & 0xFF00FF00)
    {
        bits &= 0xFF00FF00;
        res += 8;
    }
    if (bits & 0xF0F0F0F0)
    {
        bits &= 0xF0F0F0F0;
        res += 4;
    }
    if (bits & 0xCCCCCCCC)
    {
        bits &= 0xCCCCCCCC;
        res += 2;
    }
    if (bits & 0xAAAAAAAA)
    {
        bits &= 0xAAAAAAAA;
        res += 1;
    }
    return res;
#else
    int res;

    if (bits == 0)
        return -1;
    res = 0;
    if (bits & 0xFFFF0000)
    {
        bits &= 0xFFFF0000;
        res += 16;
    }
    if (bits & 0xFF00FF00)
    {
        bits &= 0xFF00FF00;
        res += 8;
    }
    if (bits & 0xF0F0F0F0)
    {
        bits &= 0xF0F0F0F0;
        res += 4;
    }
    if (bits & 0xCCCCCCCC)
    {
        bits &= 0xCCCCCCCC;
        res += 2;
    }
    if (bits & 0xAAAAAAAA)
    {
        bits &= 0xAAAAAAAA;
        res += 1;
    }
    return res;
#endif
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the bit position of the lowest set bit in a word
    \param bits The word to be searched
    \return The bit number of the lowest set bit, or -1 if the word is zero. */
static __inline__ int bottom_bit(unsigned int bits)
{
    int res;
    
#if defined(SPANDSP_USE_86_ASM)
    __asm__ (" xorl %[res],%[res];\n"
             " decl %[res];\n"
             " bsfl %[bits],%[res]\n"
             : [res] "=&r" (res)
             : [bits] "rm" (bits));
    return res;
#else
    if (bits == 0)
        return -1;
    res = 31;
    if (bits & 0x0000FFFF)
    {
        bits &= 0x0000FFFF;
        res -= 16;
    }
    if (bits & 0x00FF00FF)
    {
        bits &= 0x00FF00FF;
        res -= 8;
    }
    if (bits & 0x0F0F0F0F)
    {
        bits &= 0x0F0F0F0F;
        res -= 4;
    }
    if (bits & 0x33333333)
    {
        bits &= 0x33333333;
        res -= 2;
    }
    if (bits & 0x55555555)
    {
        bits &= 0x55555555;
        res -= 1;
    }
    return res;
#endif
}
/*- End of function --------------------------------------------------------*/

/*! \brief Bit reverse a byte.
    \param data The byte to be reversed.
    \return The bit reversed version of data. */
static __inline__ uint8_t bit_reverse8(uint8_t x)
{
#if defined(__i386__)  ||  defined(__x86_64__)  ||  defined(__ppc__)  ||  defined(__powerpc__)
    /* If multiply is fast */
    return ((x*0x0802U & 0x22110U) | (x*0x8020U & 0x88440U))*0x10101U >> 16;
#else
    /* If multiply is slow, but we have a barrel shifter */
    x = (x >> 4) | (x << 4);
    x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2);
    return ((x & 0xAA) >> 1) | ((x & 0x55) << 1);
#endif
}
/*- End of function --------------------------------------------------------*/

/*! \brief Bit reverse a 16 bit word.
    \param data The word to be reversed.
    \return The bit reversed version of data. */
SPAN_DECLARE(uint16_t) bit_reverse16(uint16_t data);

/*! \brief Bit reverse a 32 bit word.
    \param data The word to be reversed.
    \return The bit reversed version of data. */
SPAN_DECLARE(uint32_t) bit_reverse32(uint32_t data);

/*! \brief Bit reverse each of the four bytes in a 32 bit word.
    \param data The word to be reversed.
    \return The bit reversed version of data. */
SPAN_DECLARE(uint32_t) bit_reverse_4bytes(uint32_t data);

#if defined(__x86_64__)
/*! \brief Bit reverse each of the eight bytes in a 64 bit word.
    \param data The word to be reversed.
    \return The bit reversed version of data. */
SPAN_DECLARE(uint64_t) bit_reverse_8bytes(uint64_t data);
#endif

/*! \brief Bit reverse each bytes in a buffer.
    \param to The buffer to place the reversed data in.
    \param from The buffer containing the data to be reversed.
    \param len The length of the data in the buffer. */
SPAN_DECLARE(void) bit_reverse(uint8_t to[], const uint8_t from[], int len);

/*! \brief Find the number of set bits in a 32 bit word.
    \param x The word to be searched.
    \return The number of set bits. */
SPAN_DECLARE(int) one_bits32(uint32_t x);

/*! \brief Create a mask as wide as the number in a 32 bit word.
    \param x The word to be searched.
    \return The mask. */
SPAN_DECLARE(uint32_t) make_mask32(uint32_t x);

/*! \brief Create a mask as wide as the number in a 16 bit word.
    \param x The word to be searched.
    \return The mask. */
SPAN_DECLARE(uint16_t) make_mask16(uint16_t x);

/*! \brief Find the least significant one in a word, and return a word
           with just that bit set.
    \param x The word to be searched.
    \return The word with the single set bit. */
static __inline__ uint32_t least_significant_one32(uint32_t x)
{
    return (x & (-(int32_t) x));
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the most significant one in a word, and return a word
           with just that bit set.
    \param x The word to be searched.
    \return The word with the single set bit. */
static __inline__ uint32_t most_significant_one32(uint32_t x)
{
#if defined(__i386__)  ||  defined(__x86_64__)  ||  defined(__ppc__)  ||  defined(__powerpc__)
    return 1 << top_bit(x);
#else
    x = make_mask32(x);
    return (x ^ (x >> 1));
#endif
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the parity of a byte.
    \param x The byte to be checked.
    \return 1 for odd, or 0 for even. */
static __inline__ int parity8(uint8_t x)
{
    x = (x ^ (x >> 4)) & 0x0F;
    return (0x6996 >> x) & 1;
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the parity of a 16 bit word.
    \param x The word to be checked.
    \return 1 for odd, or 0 for even. */
static __inline__ int parity16(uint16_t x)
{
    x ^= (x >> 8);
    x = (x ^ (x >> 4)) & 0x0F;
    return (0x6996 >> x) & 1;
}
/*- End of function --------------------------------------------------------*/

/*! \brief Find the parity of a 32 bit word.
    \param x The word to be checked.
    \return 1 for odd, or 0 for even. */
static __inline__ int parity32(uint32_t x)
{
    x ^= (x >> 16);
    x ^= (x >> 8);
    x = (x ^ (x >> 4)) & 0x0F;
    return (0x6996 >> x) & 1;
}
/*- End of function --------------------------------------------------------*/

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
