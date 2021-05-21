//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "UIImage+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageUtils

+ (instancetype)shared
{
    static OWSMessageUtils *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [self new];
    });
    return sharedMyManager;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

- (NSUInteger)unreadMessagesCount
{
    __block NSUInteger numberOfItems;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        numberOfItems = [InteractionFinder unreadCountInAllThreadsWithTransaction:transaction.unwrapGrdbRead];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread
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

- (void)updateApplicationBadgeCount
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }

    NSUInteger numberOfItems = [self unreadMessagesCount];
    [CurrentAppContext() setMainAppBadgeNumber:numberOfItems];
}

@end

NS_ASSUME_NONNULL_END
