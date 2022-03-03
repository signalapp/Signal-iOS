//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageUtils.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"

#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import "UIImage+OWS.h"
#import <YapDatabase/YapDatabase.h>
#import "SSKAsserts.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageUtils ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageUtils

+ (instancetype)sharedManager
{
    static OWSMessageUtils *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithPrimaryStorage:primaryStorage];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

- (NSUInteger)unreadMessagesCount
{
    __block NSUInteger count = 0;

    [LKStorage readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *unreadMessages = [transaction ext:TSUnreadDatabaseViewExtensionName];
        NSArray<NSString *> *allGroups = [unreadMessages allGroups];
        // FIXME: Confusingly, `allGroups` includes contact threads as well
        for (NSString *groupID in allGroups) {
            TSThread *thread = [TSThread fetchObjectWithUniqueID:groupID transaction:transaction];
            
            // Don't increase the count for muted threads or message requests
            if (thread.isMuted || thread.isMessageRequest) { continue; }
            
            BOOL isGroupThread = thread.isGroupThread;
            
            [unreadMessages enumerateKeysAndObjectsInGroup:groupID
                usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                    return;
                }
                id<OWSReadTracking> unread = (id<OWSReadTracking>)object;
                if (unread.read) {
                    NSLog(@"Found an already read message in the * unread * messages list.");
                    return;
                }
                if ([object isKindOfClass:TSIncomingMessage.class] && isGroupThread) {
                    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                    if (((TSGroupThread *)thread).isOnlyNotifyingForMentions && !incomingMessage.isUserMentioned) {
                        return;
                    }
                }
                count += 1;
            }];
        }
    }];

    return count;

    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessageRequestCount {
    __block NSUInteger count = 0;

    [LKStorage readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *unreadMessages = [transaction ext:TSUnreadDatabaseViewExtensionName];
        NSArray<NSString *> *allGroups = [unreadMessages allGroups];
        // FIXME: Confusingly, `allGroups` includes contact threads as well
        for (NSString *groupID in allGroups) {
            TSThread *thread = [TSThread fetchObjectWithUniqueID:groupID transaction:transaction];
            
            // Only increase the count for message requests
            if (![thread isMessageRequestUsingTransaction:transaction]) { continue; }
            
            [unreadMessages enumerateKeysAndObjectsInGroup:groupID
                usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                    return;
                }
                id<OWSReadTracking> unread = (id<OWSReadTracking>)object;
                if (unread.read) {
                    NSLog(@"Found an already read message in the * unread * messages list.");
                    return;
                }
                count += 1;
                *stop = YES;
            }];
        }
    }];

    return count;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        id databaseView = [transaction ext:TSUnreadDatabaseViewExtensionName];
        OWSAssertDebug(databaseView);
        numberOfItems = ([databaseView numberOfItemsInAllGroups] - [databaseView numberOfItemsInGroup:thread.uniqueId]);
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
