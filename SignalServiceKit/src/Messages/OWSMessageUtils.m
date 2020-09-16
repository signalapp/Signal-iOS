//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

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
