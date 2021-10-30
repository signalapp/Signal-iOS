//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageUtils.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "MessageSender.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import "UIImage+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageUtils

+ (NSUInteger)unreadMessagesCount
{
    __block NSUInteger numberOfItems;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        numberOfItems = [InteractionFinder unreadCountInAllThreadsWithTransaction:transaction.unwrapGrdbRead];
    }];

    return numberOfItems;
}

+ (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread
{
    __block NSUInteger numberOfItems;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSUInteger allCount = [InteractionFinder unreadCountInAllThreadsWithTransaction:transaction.unwrapGrdbRead];
        InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
        NSUInteger threadCount = [interactionFinder unreadCountWithTransaction:transaction.unwrapGrdbRead];
        numberOfItems = (allCount - threadCount);
    }];

    return numberOfItems;
}

@end

NS_ASSUME_NONNULL_END
