//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptsProcessor.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSReadReceipt.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSReadReceiptsProcessorMarkedMessageAsReadNotification =
    @"OWSReadReceiptsProcessorMarkedMessageAsReadNotification";

@interface OWSReadReceiptsProcessor ()

@property (nonatomic, readonly) NSArray<OWSReadReceipt *> *readReceipts;
@property (nonatomic, readonly) TSStorageManager *storageManager;

@end

@implementation OWSReadReceiptsProcessor

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts
                      storageManager:(TSStorageManager *)storageManager;
{
    self = [super init];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];
    _storageManager = storageManager;

    return self;
}

- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
                           storageManager:(TSStorageManager *)storageManager
{
    NSMutableArray<OWSReadReceipt *> *readReceipts = [NSMutableArray new];
    for (OWSSignalServiceProtosSyncMessageRead *readReceiptProto in readReceiptProtos) {
        OWSReadReceipt *readReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:readReceiptProto.sender timestamp:readReceiptProto.timestamp];
        if (readReceipt.isValid) {
            [readReceipts addObject:readReceipt];
        } else {
            DDLogError(@"%@ Received invalid read receipt: %@", self.tag, readReceipt.validationErrorMessages);
        }
    }

    return [self initWithReadReceipts:[readReceipts copy] storageManager:storageManager];
}

- (instancetype)initWithIncomingMessage:(TSIncomingMessage *)message storageManager:(TSStorageManager *)storageManager
{
    // Only groupthread sets authorId, thus this crappy code.
    // TODO ALL incoming messages should have an authorId.
    NSString *messageAuthorId;
    if (message.authorId) { // Group Thread
        messageAuthorId = message.authorId;
    } else { // Contact Thread
        messageAuthorId = [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
    }

    OWSReadReceipt *readReceipt = [OWSReadReceipt firstWithSenderId:messageAuthorId timestamp:message.timestamp];
    if (readReceipt) {
        DDLogInfo(@"%@ Found prior read receipt for incoming message.", self.tag);
        return [self initWithReadReceipts:@[ readReceipt ] storageManager:storageManager];
    } else {
        // no-op
        return [self initWithReadReceipts:@[] storageManager:storageManager];
    }
}

- (void)process
{
    DDLogDebug(@"%@ Processing %ld read receipts.", self.tag, (unsigned long)self.readReceipts.count);
    for (OWSReadReceipt *readReceipt in self.readReceipts) {
        TSIncomingMessage *message =
            [TSIncomingMessage findMessageWithAuthorId:readReceipt.senderId timestamp:readReceipt.timestamp];
        if (message) {
            OWSAssert(message.thread);

            // Mark all unread messages in this thread that are older than message specified in the read
            // receipt.
            NSMutableArray<id<OWSReadTracking>> *interactionsToMarkAsRead = [NSMutableArray new];
            [self.storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [[transaction ext:TSUnseenDatabaseViewExtensionName]
                    enumerateRowsInGroup:message.uniqueThreadId
                              usingBlock:^(NSString *collection,
                                  NSString *key,
                                  id object,
                                  id metadata,
                                  NSUInteger index,
                                  BOOL *stop) {

                                  TSInteraction *interaction = object;
                                  if (interaction.timestampForSorting > message.timestampForSorting) {
                                      *stop = YES;
                                      return;
                                  }

                                  id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
                                  OWSAssert(!possiblyRead.read);
                                  [interactionsToMarkAsRead addObject:possiblyRead];
                              }];

                for (id<OWSReadTracking> interaction in interactionsToMarkAsRead) {
                    // * Don't send a read receipt in response to a read receipt.
                    // * Don't update expiration; we'll do that in the next statement.
                    [interaction markAsReadWithTransaction:transaction sendReadReceipt:NO updateExpiration:NO];

                    // Update expiration using the timestamp from the readReceipt.
                    [OWSDisappearingMessagesJob setExpirationForMessage:(TSMessage *)interaction
                                                    expirationStartedAt:readReceipt.timestamp];

                    // Fire event that will cancel any pending notifications for this message.
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:OWSReadReceiptsProcessorMarkedMessageAsReadNotification
                                          object:(TSMessage *)interaction];
                    });
                }
            }];

            // If it was previously saved, no need to keep it around any longer.
            [readReceipt remove];
        } else {
            DDLogDebug(@"%@ Received read receipt for an unknown message. Saving it for later.", self.tag);
            [readReceipt save];
        }
    }
}

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
