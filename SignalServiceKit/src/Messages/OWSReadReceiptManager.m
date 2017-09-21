//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "OWSMessageSender.h"
#import "OWSReadReceipt.h"
#import "OWSReadReceiptsMessage.h"
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

    return [self initWithMessageSender:messageSender];
}

- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    _messageSender = messageSender;

    _toLinkedDevicesReadReceiptMap = [NSMutableDictionary new];

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(databaseViewRegistrationComplete)
                                                 name:kNSNotificationName_DatabaseViewRegistrationComplete
                                               object:nil];

    // Try to start processing.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scheduleProcessing];
    });

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

        NSArray<OWSReadReceipt *> *readReceiptsToSend = [self.toLinkedDevicesReadReceiptMap allValues];
        [self.toLinkedDevicesReadReceiptMap removeAllObjects];
        if (readReceiptsToSend.count > 0) {
            OWSReadReceiptsMessage *message = [[OWSReadReceiptsMessage alloc] initWithReadReceipts:readReceiptsToSend];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.messageSender sendMessage:message
                    success:^{
                        DDLogInfo(@"%@ Successfully sent %zd read receipt to linked devices.",
                            self.tag,
                            readReceiptsToSend.count);
                    }
                    failure:^(NSError *error) {
                        DDLogError(@"%@ Failed to send read receipt to linked devices with error: %@", self.tag, error);
                    }];
            });
        }
    }
}

- (void)messageWasReadLocally:(TSIncomingMessage *)message;
{
    @synchronized(self)
    {
        NSString *threadUniqueId = message.uniqueThreadId;
        OWSAssert(threadUniqueId.length > 0);

        NSString *messageAuthorId = message.messageAuthorId;
        OWSAssert(messageAuthorId.length > 0);

        OWSReadReceipt *newReadReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:messageAuthorId timestamp:message.timestamp];

        OWSReadReceipt *_Nullable oldReadReceipt = self.toLinkedDevicesReadReceiptMap[threadUniqueId];
        if (oldReadReceipt && oldReadReceipt.timestamp > newReadReceipt.timestamp) {
            // If there's an existing read receipt for the same thread with
            // a newer timestamp, discard the new read receipt.
            return;
        }

        self.toLinkedDevicesReadReceiptMap[threadUniqueId] = newReadReceipt;

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
