//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"
#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIPage

#pragma mark - Factory Methods

- (NSString *)name
{
    OWSFailNoProdLog(@"This method should be overriden in subclasses.");

    return nil;
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSFailNoProdLog(@"This method should be overriden in subclasses.");

    return nil;
}

@end

NS_ASSUME_NONNULL_END
