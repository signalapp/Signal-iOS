//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/NSObject+OWS.h>
#import <SignalServiceKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

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

#define ENFORCE_SINGLETONS

#endif

#ifdef ENFORCE_SINGLETONS

#define OWSSingletonAssertFlag() static BOOL _isSingletonCreated = NO;

#define OWSSingletonAssertInit()                                                                                       \
    @synchronized([self class]) {                                                                                      \
        if (!AppContextObjcBridge.CurrentAppContext.isRunningTests) {                                                  \
            OWSAssertDebug(!_isSingletonCreated);                                                                      \
            _isSingletonCreated = YES;                                                                                 \
        }                                                                                                              \
    }

#define OWSSingletonAssert() OWSSingletonAssertFlag() OWSSingletonAssertInit()

#else

#define OWSSingletonAssertFlag()
#define OWSSingletonAssertInit()
#define OWSSingletonAssert()

#endif

NS_ASSUME_NONNULL_END
