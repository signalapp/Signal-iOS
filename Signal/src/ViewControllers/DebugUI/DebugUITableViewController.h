//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIPage.h"
#import <SignalUI/OWSTableViewController.h>

#ifdef USE_DEBUG_UI

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface DebugUITableViewController : OWSTableViewController

+ (void)presentDebugUIFromViewController:(UIViewController *)fromViewController;

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END

#endif
