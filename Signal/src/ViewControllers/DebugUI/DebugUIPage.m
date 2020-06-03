//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import "OWSTableViewController.h"

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END

#endif
