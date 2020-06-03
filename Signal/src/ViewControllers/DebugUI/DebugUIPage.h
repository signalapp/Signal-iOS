//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"

// This preprocessor symbol controls whether or not the Debug UI is active.
//
// To show the DebugUI in production builds, comment out the #ifdef and #endif
#ifdef DEBUG

#define USE_DEBUG_UI

NS_ASSUME_NONNULL_BEGIN

@class OWSTableSection;
@class TSThread;

@interface DebugUIPage : NSObject

- (NSString *)name;

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread NS_SWIFT_NAME(section(thread:));

@end

NS_ASSUME_NONNULL_END

#endif
