//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/DebuggerUtils.h>
#import <SignalServiceKit/OWSLogs.h>

NS_ASSUME_NONNULL_BEGIN

#ifndef OWSAssert

#define CONVERT_TO_STRING(X) #X
#define CONVERT_EXPR_TO_STRING(X) CONVERT_TO_STRING(X)

#define OWSAssertDebugUnlessRunningTests(X)                                                                            \
    do {                                                                                                               \
        if (!CurrentAppContext().isRunningTests) {                                                                     \
            OWSAssertDebug(X);                                                                                         \
        }                                                                                                              \
    } while (NO)

#ifdef DEBUG

#define USE_ASSERTS

// OWSAssertDebug() and OWSFailDebug() should be used in Obj-C methods.
// OWSCAssertDebug() and OWSCFailDebug() should be used in free functions.

#define OWSAssertDebug(X)                                                                                              \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSLogError(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                           \
            OWSLogFlush();                                                                                             \
            NSAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                           \
        }                                                                                                              \
    } while (NO)

#define OWSCAssertDebug(X)                                                                                             \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSLogError(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                           \
            OWSLogFlush();                                                                                             \
            NSCAssert(0, @"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                          \
        }                                                                                                              \
    } while (NO)

#define OWSFailWithoutLogging(message, ...)                                                                            \
    do {                                                                                                               \
        NSString *formattedMessage = [NSString stringWithFormat:message, ##__VA_ARGS__];                               \
        if (IsDebuggerAttached()) {                                                                                    \
            TrapDebugger();                                                                                            \
        } else {                                                                                                       \
            NSAssert(0, formattedMessage);                                                                             \
        }                                                                                                              \
    } while (NO)

#define OWSCFailWithoutLogging(message, ...)                                                                           \
    do {                                                                                                               \
        NSString *formattedMessage = [NSString stringWithFormat:message, ##__VA_ARGS__];                               \
        NSCAssert(0, formattedMessage);                                                                                \
    } while (NO)

#define OWSFailNoFormat(message)                                                                                       \
    do {                                                                                                               \
        OWSLogError(@"%@", message);                                                                                   \
        OWSLogFlush();                                                                                                 \
        NSAssert(0, message);                                                                                          \
    } while (NO)

#define OWSCFailNoFormat(message)                                                                                      \
    do {                                                                                                               \
        OWSLogError(@"%@", message);                                                                                   \
        OWSLogFlush();                                                                                                 \
        NSCAssert(0, message);                                                                                         \
    } while (NO)

#else

#define OWSAssertDebug(X)
#define OWSCAssertDebug(X)
#define OWSFailWithoutLogging(message, ...)
#define OWSCFailWithoutLogging(message, ...)
#define OWSFailNoFormat(X)
#define OWSCFailNoFormat(X)

#endif

#endif

// Like OWSAssertDebug, but will fail in production, terminating the app
#define OWSPrecondition(X)                                                                                             \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSFail(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                               \
        }                                                                                                              \
    } while (NO)

#define OWSCPrecondition(X)                                                                                            \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSCFail(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                              \
        }                                                                                                              \
    } while (NO)

#define OWSAbstractMethod() OWSFail(@"Method needs to be implemented by subclasses.")

// This macro is intended for use in Objective-C.
#define OWSAssertIsOnMainThread() OWSCAssertDebug([NSThread isMainThread])

#define OWSFailDebug(_messageFormat, ...)                                                                              \
    do {                                                                                                               \
        OWSLogError(_messageFormat, ##__VA_ARGS__);                                                                    \
        OWSFailWithoutLogging(_messageFormat, ##__VA_ARGS__);                                                          \
    } while (0)

#define OWSCFailDebug(_messageFormat, ...)                                                                             \
    do {                                                                                                               \
        OWSLogError(_messageFormat, ##__VA_ARGS__);                                                                    \
        OWSCFailWithoutLogging(_messageFormat, ##__VA_ARGS__);                                                         \
    } while (NO)

void SwiftExit(NSString *message, const char *file, const char *function, int line);

#define OWSFail(_messageFormat, ...)                                                                                   \
    do {                                                                                                               \
        OWSFailDebug(_messageFormat, ##__VA_ARGS__);                                                                   \
                                                                                                                       \
        NSString *_message = [NSString stringWithFormat:_messageFormat, ##__VA_ARGS__];                                \
        SwiftExit(_message, __FILE__, __PRETTY_FUNCTION__, __LINE__);                                                  \
    } while (0)

#define OWSCFail(_messageFormat, ...)                                                                                  \
    do {                                                                                                               \
        OWSCFailDebug(_messageFormat, ##__VA_ARGS__);                                                                  \
                                                                                                                       \
        NSString *_message = [NSString stringWithFormat:_messageFormat, ##__VA_ARGS__];                                \
        SwiftExit(_message, __FILE__, __PRETTY_FUNCTION__, __LINE__);                                                  \
    } while (NO)

__attribute__((annotate("returns_localized_nsstring"))) static inline NSString *LocalizationNotNeeded(NSString *s)
{
    return s;
}

NS_ASSUME_NONNULL_END
