//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface DebugUITableViewController : OWSTableViewController

+ (void)presentDebugUIFromViewController:(UIViewController *)fromViewController;

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END
