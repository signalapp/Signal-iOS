//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalMessaging/Environment.h>

NS_ASSUME_NONNULL_BEGIN

@interface MockEnvironment : Environment

+ (MockEnvironment *)activate;

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
