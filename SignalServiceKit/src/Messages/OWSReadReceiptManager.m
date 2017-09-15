//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "OWSMessageSender.h"
#import "OWSReadReceipt.h"
#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSReadReceiptsForSenderMessage.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TextSecureKitEnv.h"
#import "Threading.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// A map of "thread unique id"-to-"read receipt" for read receipts that
// we will send to our linked devices.
//
// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, OWSReadReceipt *> *toLinkedDevicesReadReceiptMap;

// A map of "recipient id"-to-"timestamp list" for read receipts that
// we will send to senders.
//
// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *toSenderReadReceiptMap;

// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic) BOOL isProcessing;

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

    return [self initWithMessageSender:messageSender
    ];
}

- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    _messageSender = messageSender;

    _toLinkedDevicesReadReceiptMap = [NSMutableDictionary new];
    _toSenderReadReceiptMap = [NSMutableDictionary new];

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(databaseViewRegistrationComplete)
                                                 name:kNSNotificationName_DatabaseViewRegistrationComplete
                                               object:nil];

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
    DispatchMainThreadSafe(^{
        @synchronized(self)
        {
            if ([TSDatabaseView hasPendingViewRegistrations]) {
                return;
            }
            if (self.isProcessing) {
                return;
            }

            self.isProcessing = YES;

            // Process read receipts every N seconds.
            //
            // We want a value high enough to allow us to effectively deduplicate,
            // read receipts without being so high that we risk not sending read
            // receipts due to app exit.
            const CGFloat kProcessingFrequencySeconds = 3.f;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kProcessingFrequencySeconds * NSEC_PER_SEC)),
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    [self process];
                });
        }
    });
}

- (void)process
{
    @synchronized(self)
    {
        self.isProcessing = NO;

        NSArray<OWSReadReceipt *> *readReceiptsForLinkedDevices = [[self.toLinkedDevicesReadReceiptMap allValues] copy];
        [self.toLinkedDevicesReadReceiptMap removeAllObjects];
        if (readReceiptsForLinkedDevices.count > 0) {
            OWSReadReceiptsForLinkedDevicesMessage *message =
                [[OWSReadReceiptsForLinkedDevicesMessage alloc] initWithReadReceipts:readReceiptsForLinkedDevices];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.messageSender sendMessage:message
                    success:^{
                        DDLogInfo(@"%@ Successfully sent %zd read receipt to linked devices.",
                            self.tag,
                            readReceiptsForLinkedDevices.count);
                    }
                    failure:^(NSError *error) {
                        DDLogError(@"%@ Failed to send read receipt to linked devices with error: %@", self.tag, error);
                    }];
            });
        }

        NSArray<OWSReadReceipt *> *readReceiptsToSend = [[self.toLinkedDevicesReadReceiptMap allValues] copy];
        [self.toLinkedDevicesReadReceiptMap removeAllObjects];
        if (self.toSenderReadReceiptMap.count > 0) {
            for (NSString *recipientId in self.toSenderReadReceiptMap) {
                NSArray<NSNumber *> *timestamps = self.toSenderReadReceiptMap[recipientId];
                OWSAssert(timestamps.count > 0);

                TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
                OWSReadReceiptsForSenderMessage *message =
                    [[OWSReadReceiptsForSenderMessage alloc] initWithThread:thread messageTimestamps:timestamps];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.messageSender sendMessage:message
                        success:^{
                            DDLogInfo(@"%@ Successfully sent %zd read receipts to sender.",
                                self.tag,
                                readReceiptsToSend.count);
                        }
                        failure:^(NSError *error) {
                            DDLogError(@"%@ Failed to send read receipts to sender with error: %@", self.tag, error);
                        }];
                });
            }
            [self.toSenderReadReceiptMap removeAllObjects];
        }
    }
}

- (void)messageWasReadLocally:(TSIncomingMessage *)message;
{
    @synchronized(self)
    {
        NSString *threadUniqueId = message.thread.uniqueId;
        OWSAssert(threadUniqueId.length > 0);

        // Only groupthread sets authorId, thus this crappy code.
        // TODO Refactor so that ALL incoming messages have an authorId.
        NSString *messageAuthorId;
        if (message.authorId) {
            // Group Thread
            messageAuthorId = message.authorId;
        } else {
            // Contact Thread
            messageAuthorId = [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
        }
        OWSAssert(messageAuthorId.length > 0);

        OWSReadReceipt *newReadReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:messageAuthorId timestamp:message.timestamp];

        BOOL modified = NO;
        OWSReadReceipt *_Nullable oldReadReceipt = self.toLinkedDevicesReadReceiptMap[threadUniqueId];
        if (oldReadReceipt && oldReadReceipt.timestamp > newReadReceipt.timestamp) {
            // If there's an existing read receipt for the same thread with
            // a newer timestamp, discard the new read receipt.
        } else {
            self.toLinkedDevicesReadReceiptMap[threadUniqueId] = newReadReceipt;

            modified = YES;
        }

        NSMutableArray<NSNumber *> *_Nullable timestamps = self.toSenderReadReceiptMap[messageAuthorId];
        if (!timestamps) {
            timestamps = [NSMutableArray new];
            self.toSenderReadReceiptMap[messageAuthorId] = timestamps;
        }
        [timestamps addObject:@(message.timestamp)];

        [self scheduleProcessing];
    }
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
