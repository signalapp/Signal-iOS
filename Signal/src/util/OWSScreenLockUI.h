//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSScreenLockUI : NSObject

@property (nonatomic, readonly) UIWindow *screenBlockingWindow;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shared;

- (void)setupWithRootWindow:(UIWindow *)rootWindow;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
