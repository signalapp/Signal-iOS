/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.ac by autoheader.  */

/* Make use of ARM4 assembly optimizations */
/* #undef ARM4_ASM */

/* Make use of ARM5E assembly optimizations */
/* #undef ARM5E_ASM */

/* Make use of Blackfin assembly optimizations */
/* #undef BFIN_ASM */

/* Disable all parts of the API that are using floats */
/* #undef DISABLE_FLOAT_API */

/* Disable VBR and VAD from the co/Users/petar/Downloads/Disgaea_menu.zipdec */
/* #undef DISABLE_VBR */

/* Enable valgrind extra checks */
/* #undef ENABLE_VALGRIND */

/* Symbol v/Users/petar/Downloads/Disgaea_menu.zipisibility prefix */
#define EXPORT __attribute__((visibility("default")))

/* Debug fixed-point implementation */
/* #undef FIXED_DEBUG */

/* Compile as fixed-point */
#define FIXED_POINT

/* Compile as floating-point */
/* #undef FLOATING_POINT */
//#define FLOATING_POINT

/* Define to 1 if you have the <alloca.h> header file. */
#define HAVE_ALLOCA_H 1

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* Define to 1 if you have the <getopt.h> header file. */
#define HAVE_GETOPT_H 1

/* Define to 1 if you have the `getopt_long' function. */
#define HAVE_GETOPT_LONG 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define to 1 if you have the `m' library (-lm). */
#define HAVE_LIBM 1

/* Define to 1 if you have the `winmm' library (-lwinmm). */
/* #undef HAVE_LIBWINMM */

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <sys/audioio.h> header file. */
/* #undef HAVE_SYS_AUDIOIO_H */

/* Define to 1 if you have the <sys/soundcard.h> header file. */
/* #undef HAVE_SYS_SOUNDCARD_H */

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME ""

/* Define to the full name and version of this package. */
#define PACKAGE_STRING ""

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME ""

/* Define to the version of this package. */
#define PACKAGE_VERSION ""

/* The size of `int', as computed by sizeof. */
#define SIZEOF_INT 4

/* The size of `long', as computed by sizeof. */
#define SIZEOF_LONG 8

/* The size of `short', as computed by sizeof. */
#define SIZEOF_SHORT 2

/* Version extra */
#define SPEEX_EXTRA_VERSION ""

/* Version major */
#define SPEEX_MAJOR_VERSION 1

/* Version micro */
#define SPEEX_MICRO_VERSION 16

/* Version minor */
#define SPEEX_MINOR_VERSION 1

/* Complete version string */
#define SPEEX_VERSION "1.2rc1"

/* Define to 1 if you have the ANSI C header files. */
#define STDC_HEADERS 1

/* Enable support for TI C55X DSP */
/* #undef TI_C55X */

/* Make use of alloca */
/* #undef USE_ALLOCA */

/* Use FFTW3 for FFT */
/* #undef USE_GPL_FFTW3 */

/* Use Intel Math Kernel Library for FFT */
/* #undef USE_INTEL_MKL */

/* Use KISS Fast Fourier Transform */
#define USE_KISS_FFT 

/* Use FFT from OggVorbis */
/* #undef USE_SMALLFT */

/* Use C99 variable-size arrays */
#define VAR_ARRAYS 

/* Define to 1 if your processor stores words with the most significant byte
   first (like Motorola and SPARC, unlike Intel and VAX). */
/* #undef WORDS_BIGENDIAN */

/* Enable SSE support */
/* #undef _USE_SSE */

/* Define to empty if `const' does not conform to ANSI C. */
/* #undef const */

/* Define to `__inline__' or `__inline' if that's what the C compiler
   calls it, or to nothing if 'inline' is not supported under any name.  */
#ifndef __cplusplus
/* #undef inline */
#endif

/* Define to equivalent of C99 restrict keyword, or to nothing if this is not
   supported. Do not define if restrict is supported directly. */
#define restrict __restrict
