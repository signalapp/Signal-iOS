//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalUI/OWSViewController.h>
#import <SignalUI/ScreenLockViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ShareViewDelegate;

@interface SAEScreenLockViewController : ScreenLockViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate;

@end

NS_ASSUME_NONNULL_END
