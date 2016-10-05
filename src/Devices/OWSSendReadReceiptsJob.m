//  Created by Michael Kirk on 9/24/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSSendReadReceiptsJob.h"
#import "OWSReadReceipt.h"
#import "OWSReadReceiptsMessage.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSMessagesManager+sendMessages.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSendReadReceiptsJob ()

@property (atomic) NSMutableArray<OWSReadReceipt *> *readReceiptsQueue;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property BOOL isObserving;

@end

@implementation OWSSendReadReceiptsJob

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

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

- (void)runWith:(TSIncomingMessage *)message
{
    // Only groupthread sets authorId, thus this crappy code.
    // TODO Refactor so that ALL incoming messages have an authorId.
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
