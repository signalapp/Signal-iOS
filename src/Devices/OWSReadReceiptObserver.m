//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceiptObserver.h"
#import "OWSReadReceipt.h"
#import "OWSReadReceiptsMessage.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSMessagesManager+sendMessages.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptObserver ()

@property (atomic) NSMutableArray<OWSReadReceipt *> *readReceiptsQueue;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property BOOL isObserving;

@end

@implementation OWSReadReceiptObserver

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _readReceiptsQueue = [NSMutableArray new];
    _messagesManager = messagesManager;
    _isObserving = NO;

    return self;
}

- (void)startObserving
{
    if (self.isObserving) {
        return;
    }

    self.isObserving = true;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleReadNotification:)
                                                 name:TSIncomingMessageWasReadOnThisDeviceNotification
                                               object:nil];
}

- (void)handleReadNotification:(NSNotification *)notification
{
    if (![notification.object isKindOfClass:[TSIncomingMessage class]]) {
        DDLogError(@"Read receipt notifier got unexpected object: %@", notification.object);
        return;
    }

    TSIncomingMessage *message = (TSIncomingMessage *)notification.object;

    // Only groupthread sets authorId, thus this crappy code.
    // TODO ALL incoming messages should have an authorId.
    NSString *messageAuthorId;
    if (message.authorId) { // Group Thread
        messageAuthorId = message.authorId;
    } else { // Contact Thread
        messageAuthorId = [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
    }

    OWSReadReceipt *readReceipt = [[OWSReadReceipt alloc] initWithSenderId:messageAuthorId timestamp:message.timestamp];
    [self.readReceiptsQueue addObject:readReceipt];

    // Wait a bit to bundle up read receipts into one request.
    __weak typeof(self) weakSelf = self;
    [weakSelf performSelector:@selector(sendAllReadReceiptsInQueue) withObject:nil afterDelay:2.0];
}

- (void)sendAllReadReceiptsInQueue
{
    // Synchronized so we don't lose any read receipts while replacing the queue
    __block NSArray<OWSReadReceipt *> *receiptsToSend;
    @synchronized(self)
    {
        if (self.readReceiptsQueue.count > 0) {
            receiptsToSend = [self.readReceiptsQueue copy];
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

    [self.messagesManager sendMessage:message
        inThread:nil
        success:^{
            DDLogInfo(@"Successfully sent %ld read receipt", (unsigned long)readReceipts.count);
        }
        failure:^{
            DDLogError(@"Failed to send read receipt");
        }];
}

@end

NS_ASSUME_NONNULL_END
