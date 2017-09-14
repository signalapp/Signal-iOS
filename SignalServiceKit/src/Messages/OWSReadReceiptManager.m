//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "OWSMessageSender.h"
#import "OWSReadReceipt.h"
#import "OWSReadReceiptsMessage.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptManager ()

//@property (nonatomic, readonly) id<OWSCallMessageHandler> callMessageHandler;
//@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
//@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
//@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;
//@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
//@property (nonatomic, readonly) OWSIdentityManager *identityManager;

@property (atomic) NSMutableArray<OWSReadReceipt *> *readReceiptsQueue;
@property BOOL isObserving;

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
    //    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    //    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    //    id<ContactsManagerProtocol> contactsManager = [TextSecureKitEnv sharedEnv].contactsManager;
    //    id<OWSCallMessageHandler> callMessageHandler = [TextSecureKitEnv sharedEnv].callMessageHandler;
    //    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    //    OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initWithMessageSender:messageSender];
}

- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    //    _storageManager = storageManager;
    //    _networkManager = networkManager;
    //    _callMessageHandler = callMessageHandler;
    //    _contactsManager = contactsManager;
    //    _contactsUpdater = contactsUpdater;
    //    _identityManager = identityManager;
    _messageSender = messageSender;

    //    _dbConnection = storageManager.newDatabaseConnection;
    //    _incomingMessageFinder = [[OWSIncomingMessageFinder alloc] initWithDatabase:storageManager.database];
    //    _blockingManager = [OWSBlockingManager sharedManager];

    _readReceiptsQueue = [NSMutableArray new];
    _messageSender = messageSender;
    _isObserving = NO;

    OWSSingletonAssert();

    //    [self startObserving];

    return self;
}

//- (void)dealloc
//{
//    [[NSNotificationCenter defaultCenter] removeObserver:self];
//}

- (void)enqueueIncomingMessage:(TSIncomingMessage *)message;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Only groupthread sets authorId, thus this crappy code.
        // TODO Refactor so that ALL incoming messages have an authorId.
        NSString *messageAuthorId;
        if (message.authorId) { // Group Thread
            messageAuthorId = message.authorId;
        } else { // Contact Thread
            messageAuthorId = [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
        }

        OWSReadReceipt *readReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:messageAuthorId timestamp:message.timestamp];
        [self.readReceiptsQueue addObject:readReceipt];

        // Wait a bit to bundle up read receipts into one request.
        __weak typeof(self) weakSelf = self;
        [weakSelf performSelector:@selector(sendAllReadReceiptsInQueue) withObject:nil afterDelay:2.0];
    });
}

- (void)sendAllReadReceiptsInQueue
{
    // Synchronized so we don't lose any read receipts while replacing the queue
    __block NSArray<OWSReadReceipt *> *_Nullable receiptsToSend;
    @synchronized(self)
    {
        if (self.readReceiptsQueue.count > 0) {
            receiptsToSend = self.readReceiptsQueue;
            self.readReceiptsQueue = [NSMutableArray new];
        }
    }

    if (receiptsToSend) {
        [self sendReadReceipts:receiptsToSend];
    } else {
        DDLogVerbose(@"Read receipts queue already drained.");
    }
}

- (void)sendReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts
{
    OWSReadReceiptsMessage *message = [[OWSReadReceiptsMessage alloc] initWithReadReceipts:readReceipts];

    [self.messageSender sendMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent %ld read receipt", self.tag, (unsigned long)readReceipts.count);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send read receipt with error: %@", self.tag, error);
        }];
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
