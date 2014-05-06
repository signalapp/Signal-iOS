/*
 * SpanDSP - a series of DSP components for telephony
 *
 * timing.h - Provide access to the Pentium/Athlon TSC timer register
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
 * $Id: timing.h,v 1.14 2009/09/04 14:38:47 steveu Exp $
 */

#if !defined(_SPANDSP_TIMING_H_)
#define _SPANDSP_TIMING_H_

#if defined(__cplusplus)
extern "C"
{
#endif

#if defined(__MSVC__)
__declspec(naked) unsigned __int64 __cdecl rdtscll(void)
{
   __asm
   {
      rdtsc
      ret       ; return value at EDX:EAX
   }
}
/*- End of function --------------------------------------------------------*/
#elif defined(__GNUC__)
#if defined(__i386__)
static __inline__ uint64_t rdtscll(void)
{
    uint64_t now;

    __asm__ __volatile__(" rdtsc\n" : "=A" (now));
    return now;
}
/*- End of function --------------------------------------------------------*/
#elif defined(__x86_64__)
static __inline__ uint64_t rdtscll(void)
{
    uint32_t a;
    uint32_t d;

    /* For x86_64 we need to merge the result in 2 32 bit registers
       into one clean 64 bit result. */
    __asm__ __volatile__(" rdtsc\n" : "=a" (a), "=d" (d));
    return ((uint64_t) a) | (((uint64_t) d) << 32);
}
/*- End of function --------------------------------------------------------*/
#else
static __inline__ uint64_t rdtscll(void)
{
    /* This architecture doesn't have a suitable timer */
    return 0llu;
}
/*- End of function --------------------------------------------------------*/
#endif
#endif

#if defined(__cplusplus)
}
#endif

#endif
/*- End of file ------------------------------------------------------------*/
