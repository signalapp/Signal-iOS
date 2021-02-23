//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "DebugUIScreenshots.h"
#import "DebugContactsUtils.h"
#import "DebugUIContacts.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIScreenshots

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Screenshots";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    [items addObjectsFromArray:@[
        [OWSTableItem itemWithTitle:@"Delete all threads"
                        actionBlock:^{
                            [DebugUIScreenshots deleteAllThreads];
                        }],
        [OWSTableItem itemWithTitle:@"Make Threads for Screenshots"
                        actionBlock:^{
                            [DebugUIScreenshots makeThreadsForScreenshots];
                        }],
    ]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

@end

NS_ASSUME_NONNULL_END

#endif
