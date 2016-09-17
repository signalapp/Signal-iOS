//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosSyncMessageRead;
@class OWSReadReceipt;
@class TSIncomingMessage;

extern NSString *const OWSReadReceiptsProcessorMarkedMessageAsReadNotification;

@interface OWSReadReceiptsProcessor : NSObject

- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos;
- (instancetype)initWithIncomingMessage:(TSIncomingMessage *)incomingMessage;
- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)process;

@end

NS_ASSUME_NONNULL_END
