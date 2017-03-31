//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

@class TSThread;

@interface DebugUITableViewController : OWSTableViewController

+ (void)presentDebugUIForThread:(TSThread *)thread
             fromViewController:(UIViewController *)fromViewController;

@end
