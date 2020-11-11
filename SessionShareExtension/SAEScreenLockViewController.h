//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalUtilitiesKit/OWSViewController.h>
#import <SignalUtilitiesKit/ScreenLockViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ShareViewDelegate;

@interface SAEScreenLockViewController : ScreenLockViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate;

@end

NS_ASSUME_NONNULL_END
