//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import "OWSMessageSender.h"
#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSReadReceiptsForSenderMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "OWSSyncConfigurationMessage.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"
#import "Threading.h"

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
    OWSAssert(sentTimestamp > 0);

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
    OWSAssert(recipientId.length > 0);
    OWSAssert(timestamp > 0);

    NSMutableDictionary<NSString *, NSNumber *> *recipientMapCopy = [self.recipientMap mutableCopy];
    recipientMapCopy[recipientId] = @(timestamp);
    _recipientMap = [recipientMapCopy copy];
}

+ (void)addRecipientId:(NSString *)recipientId
         sentTimestamp:(uint64_t)sentTimestamp
         readTimestamp:(uint64_t)readTimestamp
           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

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
    OWSAssert(transaction);

    TSRecipientReadReceipt *_Nullable recipientReadReceipt =
        [transaction objectForKey:[self uniqueIdForSentTimestamp:sentTimestamp] inCollection:[self collection]];
    return recipientReadReceipt.recipientMap;
}

+ (void)removeRecipientIdsForTimestamp:(uint64_t)sentTimestamp
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    [transaction removeObjectForKey:[self uniqueIdForSentTimestamp:sentTimestamp] inCollection:[self collection]];
}

@end

#pragma mark -

NSString *const OWSReadReceiptManagerCollection = @"OWSReadReceiptManagerCollection";
NSString *const OWSReadReceiptManagerAreReadReceiptsEnabled = @"areReadReceiptsEnabled";

@interface OWSReadReceiptManager ()

@property (nonatomic, readonly) OWSMessageSender *messageSender;

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// A map of "thread unique id"-to-"read receipt" for read receipts that
// we will send to our linked devices.
//
// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, OWSLinkedDeviceReadReceipt *> *toLinkedDevicesReadReceiptMap;

// A map of "recipient id"-to-"timestamp list" for read receipts that
// we will send to senders.
//
// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *toSenderReadReceiptMap;

// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic) BOOL isProcessing;

@property (atomic) NSNumber *areReadReceiptsEnabledCached;

@end

#pragma mark -

@implementation OWSReadReceiptManager

+ (instancetype)sharedManager
{
    static OWSReadReceiptManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;
    TSStorageManager *storageManager = [TSStorageManager sharedManager];

    return [self initWithMessageSender:messageSender storageManager:storageManager];
}

- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender
                       storageManager:(TSStorageManager *)storageManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    _messageSender = messageSender;
    _dbConnection = storageManager.newDatabaseConnection;

    _toLinkedDevicesReadReceiptMap = [NSMutableDictionary new];
    _toSenderReadReceiptMap = [NSMutableDictionary new];

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(databaseViewRegistrationComplete)
                                                 name:kNSNotificationName_DatabaseViewRegistrationComplete
                                               object:nil];

    // Try to start processing.
    [self scheduleProcessing];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)databaseViewRegistrationComplete
{
    [self scheduleProcessing];
}

// Schedules a processing pass, unless one is already scheduled.
- (void)scheduleProcessing
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            if ([TSDatabaseView hasPendingViewRegistrations]) {
                DDLogInfo(
                    @"%@ Deferring read receipt processing due to pending database view registrations.", self.tag);
                return;
            }
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
    @synchronized(self)
    {
        DDLogVerbose(@"%@ Processing read receipts.", self.tag);

        NSArray<OWSLinkedDeviceReadReceipt *> *readReceiptsForLinkedDevices =
            [self.toLinkedDevicesReadReceiptMap allValues];
        [self.toLinkedDevicesReadReceiptMap removeAllObjects];
        if (readReceiptsForLinkedDevices.count > 0) {
            OWSReadReceiptsForLinkedDevicesMessage *message =
                [[OWSReadReceiptsForLinkedDevicesMessage alloc] initWithReadReceipts:readReceiptsForLinkedDevices];

            [self.messageSender sendMessage:message
                success:^{
                    DDLogInfo(@"%@ Successfully sent %zd read receipt to linked devices.",
                        self.tag,
                        readReceiptsForLinkedDevices.count);
                }
                failure:^(NSError *error) {
                    DDLogError(@"%@ Failed to send read receipt to linked devices with error: %@", self.tag, error);
                }];
        }

        NSDictionary<NSString *, NSMutableSet<NSNumber *> *> *toSenderReadReceiptMap =
            [self.toSenderReadReceiptMap copy];
        [self.toSenderReadReceiptMap removeAllObjects];
        if (toSenderReadReceiptMap.count > 0) {
            for (NSString *recipientId in toSenderReadReceiptMap) {
                NSSet<NSNumber *> *timestamps = toSenderReadReceiptMap[recipientId];
                OWSAssert(timestamps.count > 0);

                TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
                OWSReadReceiptsForSenderMessage *message =
                    [[OWSReadReceiptsForSenderMessage alloc] initWithThread:thread
                                                          messageTimestamps:timestamps.allObjects];

                [self.messageSender sendMessage:message
                    success:^{
                        DDLogInfo(@"%@ Successfully sent %zd read receipts to sender.", self.tag, timestamps.count);
                    }
                    failure:^(NSError *error) {
                        DDLogError(@"%@ Failed to send read receipts to sender with error: %@", self.tag, error);
                    }];
            }
            [self.toSenderReadReceiptMap removeAllObjects];
        }

        BOOL didWork = (readReceiptsForLinkedDevices.count > 0 || toSenderReadReceiptMap.count > 0);

        if (didWork) {
            // Wait N seconds before processing read receipts again.
            // This allows time for a batch to accumulate.
            //
            // We want a value high enough to allow us to effectively de-duplicate,
            // read receipts without being so high that we risk not sending read
            // receipts due to app exit.
            const CGFloat kProcessingFrequencySeconds = 3.f;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kProcessingFrequencySeconds * NSEC_PER_SEC)),
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    [self process];
                });
        } else {
            self.isProcessing = NO;
        }
    }
}

#pragma mark - Mark as Read Locally

- (void)markAsReadLocallyBeforeTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
{
    OWSAssert(thread);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self markAsReadBeforeTimestamp:timestamp
                                     thread:thread
                                   wasLocal:YES
                                transaction:transaction];
        }];
    });
}

- (void)messageWasReadLocally:(TSIncomingMessage *)message
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            NSString *threadUniqueId = message.uniqueThreadId;
            OWSAssert(threadUniqueId.length > 0);

            NSString *messageAuthorId = message.messageAuthorId;
            OWSAssert(messageAuthorId.length > 0);

            OWSLinkedDeviceReadReceipt *newReadReceipt =
                [[OWSLinkedDeviceReadReceipt alloc] initWithSenderId:messageAuthorId timestamp:message.timestamp];

            OWSLinkedDeviceReadReceipt *_Nullable oldReadReceipt = self.toLinkedDevicesReadReceiptMap[threadUniqueId];
            if (oldReadReceipt && oldReadReceipt.timestamp > newReadReceipt.timestamp) {
                // If there's an existing "linked device" read receipt for the same thread with
                // a newer timestamp, discard this "linked device" read receipt.
                DDLogVerbose(@"%@ Ignoring redundant read receipt for linked devices.", self.tag);
            } else {
                DDLogVerbose(@"%@ Enqueuing read receipt for linked devices.", self.tag);
                self.toLinkedDevicesReadReceiptMap[threadUniqueId] = newReadReceipt;
            }

            if ([self areReadReceiptsEnabled]) {
                DDLogVerbose(@"%@ Enqueuing read receipt for sender.", self.tag);
                NSMutableSet<NSNumber *> *_Nullable timestamps = self.toSenderReadReceiptMap[messageAuthorId];
                if (!timestamps) {
                    timestamps = [NSMutableSet new];
                    self.toSenderReadReceiptMap[messageAuthorId] = timestamps;
                }
                [timestamps addObject:@(message.timestamp)];
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
    OWSAssert(recipientId.length > 0);
    OWSAssert(sentTimestamps);

    if (![self areReadReceiptsEnabled]) {
        DDLogInfo(@"%@ Ignoring incoming receipt message as read receipts are disabled.", self.tag);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSNumber *nsSentTimestamp in sentTimestamps) {
                UInt64 sentTimestamp = [nsSentTimestamp unsignedLongLongValue];

                NSArray<TSOutgoingMessage *> *messages
                    = (NSArray<TSOutgoingMessage *> *)[TSInteraction interactionsWithTimestamp:sentTimestamp
                                                                                       ofClass:[TSOutgoingMessage class]
                                                                               withTransaction:transaction];
                OWSAssert(messages.count <= 1);
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

- (void)applyEarlyReadReceiptsForOutgoingMessageFromLinkedDevice:(TSOutgoingMessage *)message
                                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(message);
    OWSAssert(transaction);

    uint64_t sentTimestamp = message.timestamp;
    NSDictionary<NSString *, NSNumber *> *recipientMap =
        [TSRecipientReadReceipt recipientMapForSentTimestamp:sentTimestamp transaction:transaction];
    if (!recipientMap) {
        return;
    }
    OWSAssert(recipientMap.count > 0);
    for (NSString *recipientId in recipientMap) {
        NSNumber *nsReadTimestamp = recipientMap[recipientId];
        OWSAssert(nsReadTimestamp);
        uint64_t readTimestamp = [nsReadTimestamp unsignedLongLongValue];

        [message updateWithReadRecipientId:recipientId readTimestamp:readTimestamp transaction:transaction];
    }
    [TSRecipientReadReceipt removeRecipientIdsForTimestamp:message.timestamp transaction:transaction];
}

#pragma mark - Linked Device Read Receipts

- (void)applyEarlyReadReceiptsForIncomingMessage:(TSIncomingMessage *)message
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(message);
    OWSAssert(transaction);

    NSString *senderId = message.messageAuthorId;
    uint64_t timestamp = message.timestamp;
    if (senderId.length < 1 || timestamp < 1) {
        OWSFail(@"%@ Invalid incoming message: %@ %llu", self.tag, senderId, timestamp);
        return;
    }

    OWSLinkedDeviceReadReceipt *_Nullable readReceipt =
        [OWSLinkedDeviceReadReceipt findLinkedDeviceReadReceiptWithSenderId:senderId
                                                                  timestamp:timestamp
                                                                transaction:transaction];
    if (!readReceipt) {
        return;
    }
    [message markAsReadWithTransaction:transaction sendReadReceipt:NO updateExpiration:YES];
    [readReceipt removeWithTransaction:transaction];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kIncomingMessageMarkedAsReadNotification
                                                             object:message];
}

- (void)processReadReceiptsFromLinkedDevice:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
                                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(readReceiptProtos);
    OWSAssert(transaction);

    for (OWSSignalServiceProtosSyncMessageRead *readReceiptProto in readReceiptProtos) {
        NSString *_Nullable senderId = readReceiptProto.sender;
        uint64_t timestamp = readReceiptProto.timestamp;
        BOOL isValid = senderId.length > 0 && timestamp > 0;
        if (!isValid) {
            continue;
        }
        
        NSArray<TSIncomingMessage *> *messages = (NSArray<TSIncomingMessage *> *) [TSInteraction interactionsWithTimestamp:timestamp
                                                                                                                   ofClass:[TSIncomingMessage class]
                                                                                                           withTransaction:transaction];
        if (messages.count > 0) {
            for (TSIncomingMessage *message in messages) {
                OWSAssert([message isKindOfClass:[TSIncomingMessage class]]);
                        
                [self markAsReadOnLinkedDevice:message
                                   transaction:transaction];
            }
        } else {
            // Received read receipt for unknown incoming message.
            // Persist in case we receive the incoming message later.
            OWSLinkedDeviceReadReceipt *readReceipt = [[OWSLinkedDeviceReadReceipt alloc] initWithSenderId:senderId timestamp:timestamp];
            [readReceipt saveWithTransaction:transaction];
        }
    }
}

- (void)markAsReadOnLinkedDevice:(TSIncomingMessage *)message
                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(message);
    OWSAssert(transaction);

    // Use timestampForSorting which reflects local sort order, rather than timestamp
    // which reflect sender time.
    [self markAsReadBeforeTimestamp:message.timestampForSorting
                             thread:[message threadWithTransaction:transaction]
                           wasLocal:NO
                        transaction:transaction];
}

#pragma mark - Mark As Read

- (void)markAsReadBeforeTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                         wasLocal:(BOOL)wasLocal
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(timestamp > 0);
    OWSAssert(thread);
    OWSAssert(transaction);
    
    NSMutableArray<id<OWSReadTracking>> *interactions = [NSMutableArray new];
    
    [[TSDatabaseView unseenDatabaseViewExtension:transaction]
     enumerateRowsInGroup:thread.uniqueId
     usingBlock:^(NSString *collection,
                  NSString *key,
                  id object,
                  id metadata,
                  NSUInteger index,
                  BOOL *stop) {
         
         if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
             OWSFail(
                     @"Expected to conform to OWSReadTracking: object with class: %@ collection: %@ "
                     @"key: %@",
                     [object class],
                     collection,
                     key);
             return;
         }
         id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
         
         if (possiblyRead.timestampForSorting > timestamp) {
             *stop = YES;
             return;
         }
         
         OWSAssert(!possiblyRead.read);
         if (!possiblyRead.read) {
             [interactions addObject:possiblyRead];
         }
     }];
    
    if (interactions.count < 1) {
        return;
    }
    
    if (wasLocal) {
        DDLogError(@"Marking %zd messages as read locally.", interactions.count);
    } else {
        DDLogError(@"Marking %zd messages as read by linked device.", interactions.count);
    }
    for (id<OWSReadTracking> possiblyRead in interactions) {
        [possiblyRead markAsReadWithTransaction:transaction sendReadReceipt:wasLocal updateExpiration:YES];
        
        if ([possiblyRead isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)possiblyRead;
            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kIncomingMessageMarkedAsReadNotification
                                                                     object:incomingMessage];
        }
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
        // Default to NO.
        self.areReadReceiptsEnabledCached = @([self.dbConnection boolForKey:OWSReadReceiptManagerAreReadReceiptsEnabled
                                                               inCollection:OWSReadReceiptManagerCollection]);
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (BOOL)areReadReceiptsEnabledWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    if (!self.areReadReceiptsEnabledCached) {
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            // Default to NO.
            self.areReadReceiptsEnabledCached = [transaction objectForKey:OWSReadReceiptManagerAreReadReceiptsEnabled
                                                             inCollection:OWSReadReceiptManagerCollection];
        }];
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (void)setAreReadReceiptsEnabled:(BOOL)value
{
    DDLogInfo(@"%@ setAreReadReceiptsEnabled: %d.", self.tag, value);

    [self.dbConnection setBool:value
                        forKey:OWSReadReceiptManagerAreReadReceiptsEnabled
                  inCollection:OWSReadReceiptManagerCollection];

    OWSSyncConfigurationMessage *syncConfigurationMessage =
        [[OWSSyncConfigurationMessage alloc] initWithReadReceiptsEnabled:value];
    [self.messageSender sendMessage:syncConfigurationMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent Configuration syncMessage.", self.tag);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send Configuration syncMessage with error: %@", self.tag, error);
        }];

    self.areReadReceiptsEnabledCached = @(value);
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
