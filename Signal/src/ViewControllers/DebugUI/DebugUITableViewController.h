//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface DebugUITableViewController : OWSTableViewController

+ (void)presentDebugUIFromViewController:(UIViewController *)fromViewController;

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController;

+ (BOOL)useDebugUI;

@end

NS_ASSUME_NONNULL_END

#endif
