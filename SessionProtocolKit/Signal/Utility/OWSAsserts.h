//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLogs.h"

NS_ASSUME_NONNULL_BEGIN

#ifndef OWSAssert

#define CONVERT_TO_STRING(X) #X
#define CONVERT_EXPR_TO_STRING(X) CONVERT_TO_STRING(X)

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
        NSAssert(0, formattedMessage);                                                                                 \
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
#define OWSAssert(X)                                                                                                   \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSFail(@"Assertion failed: %s", CONVERT_EXPR_TO_STRING(X));                                               \
        }                                                                                                              \
    } while (NO)

#define OWSCAssert(X)                                                                                                  \
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
        OWSLogFlush();                                                                                                 \
        OWSFailWithoutLogging(_messageFormat, ##__VA_ARGS__);                                                          \
    } while (0)

#define OWSCFailDebug(_messageFormat, ...)                                                                             \
    do {                                                                                                               \
        OWSLogError(_messageFormat, ##__VA_ARGS__);                                                                    \
        OWSLogFlush();                                                                                                 \
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

// Avoids Clang analyzer warning:
//   Value stored to 'x' during it's initialization is never read
#define SUPPRESS_DEADSTORE_WARNING(x)                                                                                  \
    do {                                                                                                               \
        (void)x;                                                                                                       \
    } while (0)

__attribute__((annotate("returns_localized_nsstring"))) static inline NSString *LocalizationNotNeeded(NSString *s)
{
    return s;
}

#define OWSGuardWithException(X, ExceptionName)                                                                        \
    do {                                                                                                               \
        if (!(X)) {                                                                                                    \
            OWSRaiseException(ExceptionName, @"Guard failed: %s", CONVERT_EXPR_TO_STRING(X));                          \
        }                                                                                                              \
    } while (NO)

#define OWSRaiseException(name, formatParam, ...)                                                                      \
    do {                                                                                                               \
        OWSLogError(@"Exception: %@ %@", name, [NSString stringWithFormat:formatParam, ##__VA_ARGS__]);                \
        OWSLogFlush();                                                                                                 \
        @throw [NSException exceptionWithName:name                                                                     \
                                       reason:[NSString stringWithFormat:formatParam, ##__VA_ARGS__]                   \
                                     userInfo:nil];                                                                    \
    } while (NO)

#define OWSRaiseExceptionWithUserInfo(name, userInfoParam, formatParam, ...)                                           \
    do {                                                                                                               \
        OWSLogError(                                                                                                   \
            @"Exception: %@ %@ %@", name, userInfoParam, [NSString stringWithFormat:formatParam, ##__VA_ARGS__]);      \
        OWSLogFlush();                                                                                                 \
        @throw [NSException exceptionWithName:name                                                                     \
                                       reason:[NSString stringWithFormat:formatParam, ##__VA_ARGS__]                   \
                                     userInfo:userInfoParam];                                                          \
    } while (NO)


// UI JANK
//
// In pursuit of smooth UI, we want to continue moving blocking operations off the main thread.
// Add `OWSJanksUI` in code paths that shouldn't be called on the main thread.
// Because we have pervasively broken this tenant, enabling it by default would be too disruptive
// but it's helpful while unjanking and maybe someday we can have it enabled by default.
//#define DEBUG_UI_JANK 1

#ifdef DEBUG
#ifdef DEBUG_UI_JANK
#define OWSJanksUI()                                                                                                   \
    do {                                                                                                               \
        OWSAssertDebug(![NSThread isMainThread])                                                                       \
    } while (NO)
#endif
#endif

#ifndef OWSJanksUI
#define OWSJanksUI()
#endif

#pragma mark - Overflow Math

#define ows_add_overflow(a, b, resultRef)                                                                              \
    do {                                                                                                               \
        BOOL _didOverflow = __builtin_add_overflow(a, b, resultRef);                                                   \
        OWSAssert(!_didOverflow);                                                                                      \
    } while (NO)

#define ows_sub_overflow(a, b, resultRef)                                                                              \
    do {                                                                                                               \
        BOOL _didOverflow = __builtin_sub_overflow(a, b, resultRef);                                                   \
        OWSAssert(!_didOverflow);                                                                                      \
    } while (NO)

#define ows_mul_overflow(a, b, resultRef)                                                                              \
    do {                                                                                                               \
        BOOL _didOverflow = __builtin_mul_overflow(a, b, resultRef);                                                   \
        OWSAssert(!_didOverflow);                                                                                      \
    } while (NO)

NS_ASSUME_NONNULL_END
