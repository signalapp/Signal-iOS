//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import "OWSTableViewController.h"

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface DebugUITableViewController : OWSTableViewController

+ (void)presentDebugUIFromViewController:(UIViewController *)fromViewController;

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END

#endif
