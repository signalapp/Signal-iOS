//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIPage.h"
#import "DebugUITableViewController.h"
#import <SignalUI/OWSTableViewController.h>

NS_ASSUME_NONNULL_BEGIN

BOOL shouldUseDebugUI(void)
{
#ifdef USE_DEBUG_UI
    return YES;
#else
    return NO;
#endif
}

void showDebugUI(TSThread *thread, UIViewController *fromViewController)
{
#ifdef USE_DEBUG_UI
    [DebugUITableViewController presentDebugUIForThread:thread fromViewController:fromViewController];
#else
    OWSCFailDebug(@"Debug UI not enabled.");
#endif
}

#ifdef DEBUG

@implementation DebugUIPage

#pragma mark - Factory Methods

- (NSString *)name
{
    OWSFailDebug(@"This method should be overridden in subclasses.");

    return @"";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSFailDebug(@"This method should be overridden in subclasses.");

    return nil;
}

@end

#endif

NS_ASSUME_NONNULL_END
