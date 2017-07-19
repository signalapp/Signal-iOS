//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosSyncMessageRead;
@class OWSReadReceipt;
@class TSIncomingMessage;
@class TSStorageManager;

extern NSString *const OWSReadReceiptsProcessorMarkedMessageAsReadNotification;

@interface OWSReadReceiptsProcessor : NSObject

/**
 * Mark existing messages as read from the given received read receipts.
 */
- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
                           storageManager:(TSStorageManager *)storageManager;

/**
 * Mark a new message as read in the rare (but does happen!) case that we receive the read receipt before the message
 * the read receipt refers to.
 */
- (instancetype)initWithIncomingMessage:(TSIncomingMessage *)incomingMessage
                         storageManager:(TSStorageManager *)storageManager;

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts
                      storageManager:(TSStorageManager *)storageManager NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)process;

@end

NS_ASSUME_NONNULL_END
