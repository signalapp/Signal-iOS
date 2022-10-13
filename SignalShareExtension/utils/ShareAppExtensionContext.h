//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
@interface ShareAppExtensionContext : NSObject <AppContext>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;

@end

NS_ASSUME_NONNULL_END
