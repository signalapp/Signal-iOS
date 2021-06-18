//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import "DebugUITableViewController.h"
#import <SignalMessaging/OWSTableViewController.h>

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
    OWSFailDebug(@"This method should be overriden in subclasses.");

    return nil;
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSFailDebug(@"This method should be overriden in subclasses.");

    return nil;
}

@end

#endif

NS_ASSUME_NONNULL_END
