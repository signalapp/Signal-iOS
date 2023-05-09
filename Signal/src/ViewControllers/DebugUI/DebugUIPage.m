//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIPage.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef USE_DEBUG_UI

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
