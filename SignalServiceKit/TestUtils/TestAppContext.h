//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface TestAppContext : NSObject <AppContext>

@property (nonatomic, readonly, class) NSString *testDebugLogsDirPath;

@end

#endif

NS_ASSUME_NONNULL_END
