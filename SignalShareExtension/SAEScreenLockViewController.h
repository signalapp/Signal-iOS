//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/OWSViewController.h>
#import <SignalUI/ScreenLockViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ShareViewDelegate;

@interface SAEScreenLockViewController : ScreenLockViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate;

@end

NS_ASSUME_NONNULL_END
