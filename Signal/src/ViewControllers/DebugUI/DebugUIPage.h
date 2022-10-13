//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIPage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

BOOL shouldUseDebugUI(void);
void showDebugUI(TSThread *thread, UIViewController *fromViewController);

// This preprocessor symbol controls whether or not the Debug UI is active.
//
// To show the DebugUI in production builds, comment out the #ifdef and #endif
#ifdef DEBUG

#define USE_DEBUG_UI

@class OWSTableSection;
@class TSThread;

@interface DebugUIPage : NSObject

- (NSString *)name;

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread NS_SWIFT_NAME(section(thread:));

@end

#endif

NS_ASSUME_NONNULL_END
