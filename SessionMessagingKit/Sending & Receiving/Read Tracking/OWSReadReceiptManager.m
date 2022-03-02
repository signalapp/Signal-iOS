//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "AppReadiness.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSStorage.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSOutgoingMessage.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "YapDatabaseConnection+OWS.h"
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kIncomingMessageMarkedAsReadNotification = @"kIncomingMessageMarkedAsReadNotification";

@interface TSRecipientReadReceipt : TSYapDatabaseObject

@property (nonatomic, readonly) uint64_t sentTimestamp;
// Map of "recipient id"-to-"read timestamp".
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *recipientMap;

@end

#pragma mark -

@implementation TSRecipientReadReceipt

+ (NSString *)collection
{
    return @"TSRecipientReadReceipt2";
}

- (instancetype)initWithSentTimestamp:(uint64_t)sentTimestamp
{
    self = [super initWithUniqueId:[TSRecipientReadReceipt uniqueIdForSentTimestamp:sentTimestamp]];

    if (self) {
        _sentTimestamp = sentTimestamp;
        _recipientMap = [NSDictionary new];
    }

    return self;
}

+ (NSString *)uniqueIdForSentTimestamp:(uint64_t)timestamp
{
    return [NSString stringWithFormat:@"%llu", timestamp];
}

- (void)addRecipientId:(NSString *)recipientId timestamp:(uint64_t)timestamp
{
    NSMutableDictionary<NSString *, NSNumber *> *recipientMapCopy = [self.recipientMap mutableCopy];
    recipientMapCopy[recipientId] = @(timestamp);
    _recipientMap = [recipientMapCopy copy];
}

+ (void)addRecipientId:(NSString *)recipientId
         sentTimestamp:(uint64_t)sentTimestamp
         readTimestamp:(uint64_t)readTimestamp
           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSRecipientReadReceipt *_Nullable recipientReadReceipt =
        [transaction objectForKey:[self uniqueIdForSentTimestamp:sentTimestamp] inCollection:[self collection]];
    if (!recipientReadReceipt) {
        recipientReadReceipt = [[TSRecipientReadReceipt alloc] initWithSentTimestamp:sentTimestamp];
    }
    [recipientReadReceipt addRecipientId:recipientId timestamp:readTimestamp];
    [recipientReadReceipt saveWithTransaction:transaction];
}

+ (nullable NSDictionary<NSString *, NSNumber *> *)recipientMapForSentTimestamp:(uint64_t)sentTimestamp
                                                                    transaction:
                                                                        (YapDatabaseReadWriteTransaction *)transaction
{
    TSRecipientReadReceipt *_Nullable recipientReadReceipt =
        [transaction objectForKey:[self uniqueIdForSentTimestamp:sentTimestamp] inCollection:[self collection]];
    return recipientReadReceipt.recipientMap;
}

+ (void)removeRecipientIdsForTimestamp:(uint64_t)sentTimestamp
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction removeObjectForKey:[self uniqueIdForSentTimestamp:sentTimestamp] inCollection:[self collection]];
}

@end

#pragma mark -

NSString *const OWSReadReceiptManagerCollection = @"OWSReadReceiptManagerCollection";
NSString *const OWSReadReceiptManagerAreReadReceiptsEnabled = @"areReadReceiptsEnabled";

@interface OWSReadReceiptManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// A map of "thread unique id"-to-"read receipt" for read receipts that
// we will send to our linked devices.
//
// Should only be accessed while synchronized on the OWSReadReceiptManager.
// @property (nonatomic, readonly) NSMutableDictionary<NSString *, OWSLinkedDeviceReadReceipt *> *toLinkedDevicesReadReceiptMap;

// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic) BOOL isProcessing;

@property (atomic) NSNumber *areReadReceiptsEnabledCached;

@end

#pragma mark -

@implementation OWSReadReceiptManager

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.readReceiptManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _dbConnection = primaryStorage.newDatabaseConnection;

    // Start processing.
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self scheduleProcessing];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSOutgoingReceiptManager *)outgoingReceiptManager
{
    return SSKEnvironment.shared.outgoingReceiptManager;
}

#pragma mark -

// Schedules a processing pass, unless one is already scheduled.
- (void)scheduleProcessing
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            if (self.isProcessing) {
                return;
            }

            self.isProcessing = YES;

            [self process];
        }
    });
}

- (void)process
{
    
}

#pragma mark - Mark as Read Locally

- (void)markAsReadLocallyBeforeSortId:(uint64_t)sortId thread:(TSThread *)thread trySendReadReceipt:(BOOL)trySendReadReceipt
{
    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self markAsReadBeforeSortId:sortId
                              thread:thread
                       readTimestamp:[NSDate millisecondTimestamp]
                  trySendReadReceipt:trySendReadReceipt
                         transaction:transaction];
    }];
}

- (void)messageWasReadLocally:(TSIncomingMessage *)message
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            NSString *messageAuthorId = message.authorId;

            if (message.thread.isGroupThread) { return; } // Don't send read receipts in group threads
            
            if ([self areReadReceiptsEnabled]) {
                [self.outgoingReceiptManager enqueueReadReceiptForEnvelope:messageAuthorId timestamp:message.timestamp];
            }

            [self scheduleProcessing];
        }
    });
}

#pragma mark - Read Receipts From Recipient

- (void)processReadReceiptsFromRecipientId:(NSString *)recipientId
                            sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                             readTimestamp:(uint64_t)readTimestamp
{
    if (![self areReadReceiptsEnabled]) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSNumber *nsSentTimestamp in sentTimestamps) {
                UInt64 sentTimestamp = [nsSentTimestamp unsignedLongLongValue];

                NSArray<TSOutgoingMessage *> *messages
                    = (NSArray<TSOutgoingMessage *> *)[TSInteraction interactionsWithTimestamp:sentTimestamp
                                                                                       ofClass:[TSOutgoingMessage class]
                                                                               withTransaction:transaction];
                if (messages.count > 0) {
                    // TODO: We might also need to "mark as read by recipient" any older messages
                    // from us in that thread.  Or maybe this state should hang on the thread?
                    for (TSOutgoingMessage *message in messages) {
                        [message updateWithReadRecipientId:recipientId
                                             readTimestamp:readTimestamp
                                               transaction:transaction];
                    }
                } else {
                    // Persist the read receipts so that we can apply them to outgoing messages
                    // that we learn about later through sync messages.
                    [TSRecipientReadReceipt addRecipientId:recipientId
                                             sentTimestamp:sentTimestamp
                                             readTimestamp:readTimestamp
                                               transaction:transaction];
                }
            }
        }];
    });
}

#pragma mark - Mark As Read

- (void)markAsReadBeforeSortId:(uint64_t)sortId
                        thread:(TSThread *)thread
                 readTimestamp:(uint64_t)readTimestamp
            trySendReadReceipt:(BOOL)trySendReadReceipt
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSMutableArray<id<OWSReadTracking>> *newlyReadList = [NSMutableArray new];

    [[TSDatabaseView unseenDatabaseViewExtension:transaction]
        enumerateKeysAndObjectsInGroup:thread.uniqueId
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                                    return;
                                }
                                id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
                                if (possiblyRead.sortId > sortId) {
                                    *stop = YES;
                                    return;
                                }

                                // Under normal circumstances !possiblyRead.read should always evaluate to true at this point, but
                                // there is a bug that can somehow cause it to be false leading to conversations permanently being
                                // stuck with "unread" messages.

                                if (!possiblyRead.read) {
                                    [newlyReadList addObject:possiblyRead];
                                }
                            }];

    if (newlyReadList.count < 1) {
        return;
    }

    for (id<OWSReadTracking> readItem in newlyReadList) {
        [readItem markAsReadAtTimestamp:readTimestamp trySendReadReceipt:trySendReadReceipt transaction:transaction];
    }
}

#pragma mark - Settings

- (void)prepareCachedValues
{
    [self areReadReceiptsEnabled];
}

- (BOOL)areReadReceiptsEnabled
{
    // We don't need to worry about races around this cached value.
    if (!self.areReadReceiptsEnabledCached) {
        self.areReadReceiptsEnabledCached = @([self.dbConnection boolForKey:OWSReadReceiptManagerAreReadReceiptsEnabled
                                                               inCollection:OWSReadReceiptManagerCollection
                                                               defaultValue:NO]);
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (void)setAreReadReceiptsEnabled:(BOOL)value
{
    [self.dbConnection setBool:value
                        forKey:OWSReadReceiptManagerAreReadReceiptsEnabled
                  inCollection:OWSReadReceiptManagerCollection];

    self.areReadReceiptsEnabledCached = @(value);
}

@end

NS_ASSUME_NONNULL_END
