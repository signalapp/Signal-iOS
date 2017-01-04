//
//  Asserts.h
//
//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef OWSAssert

#ifdef DEBUG

#define USE_ASSERTS

#define CONVERT_TO_STRING(X) #X
#define CONVERT_EXPR_TO_STRING(X) CONVERT_TO_STRING(X)

#define OWSAssert(X) \
if (!(X)) { \
NSLog(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X)); \
NSAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X)); \
}

#else

#define OWSAssert(X)

#endif

#endif
