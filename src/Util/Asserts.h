//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef OWSAssert

#ifdef DEBUG

#define USE_ASSERTS

#define CONVERT_TO_STRING(X) #X
#define CONVERT_EXPR_TO_STRING(X) CONVERT_TO_STRING(X)

// OWSAssert() and OWSFail() should be used in Obj-C methods.
// OWSCAssert() and OWSCFail() should be used in free functions.

#define OWSAssert(X)                                                                                                   \
    if (!(X)) {                                                                                                        \
        DDLogError(@"%s Assertion failed: %s", __PRETTY_FUNCTION__, CONVERT_EXPR_TO_STRING(X));                        \
        [DDLog flushLog];                                                                                              \
        NSAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                               \
    }

#define OWSCAssert(X)                                                                                                  \
    if (!(X)) {                                                                                                        \
        DDLogError(@"%s Assertion failed: %s", __PRETTY_FUNCTION__, CONVERT_EXPR_TO_STRING(X));                        \
        [DDLog flushLog];                                                                                              \
        NSCAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                              \
    }

#define OWSFail(message, ...)                                                                                          \
    {                                                                                                                  \
        NSString *formattedMessage = [NSString stringWithFormat:message, ##__VA_ARGS__];                               \
        DDLogError(@"%s %@", __PRETTY_FUNCTION__, formattedMessage);                                                   \
        [DDLog flushLog];                                                                                              \
        NSAssert(0, formattedMessage);                                                                                 \
    }

#define OWSCFail(message, ...)                                                                                         \
    {                                                                                                                  \
        if (!(X)) {                                                                                                    \
            NSString *formattedMessage = [NSString stringWithFormat:message, ##__VA_ARGS__];                           \
            DDLogError(@"%s %@", __PRETTY_FUNCTION__, formattedMessage);                                               \
            [DDLog flushLog];                                                                                          \
            NSCAssert(0, formattedMessage);                                                                            \
        }

#else

#define OWSAssert(X)
#define OWSCAssert(X)
#define OWSFail(message, ...)
#define OWSCFail(message, ...)

#endif

#endif

#pragma mark - Singleton Asserts

// The "singleton asserts" can be used to ensure
// that we only create a singleton once.
//
// The simplest way to use them is the OWSSingletonAssert() macro.
// It is intended to be used inside the singleton's initializer.
//
// If, however, a singleton has multiple possible initializers,
// you need to:
//
// 1. Use OWSSingletonAssertFlag() outside the class definition.
// 2. Use OWSSingletonAssertInit() in each initializer.
#ifdef DEBUG

#define OWSSingletonAssertFlag() static BOOL _isSingletonCreated = NO;

#define OWSSingletonAssertInit()                                                                                       \
    @synchronized([self class])                                                                                        \
    {                                                                                                                  \
        OWSAssert(!_isSingletonCreated);                                                                               \
        _isSingletonCreated = YES;                                                                                     \
    }

#define OWSSingletonAssert() OWSSingletonAssertFlag() OWSSingletonAssertInit()

#else

#define OWSSingletonAssertFlag()
#define OWSSingletonAssertInit()
#define OWSSingletonAssert()

#endif
