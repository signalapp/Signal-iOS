//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDeliveryReceipt;

@interface OWSReceiptsForSenderMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

+ (OWSReceiptsForSenderMessage *)deliveryReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                          messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps;

+ (OWSReceiptsForSenderMessage *)readReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                      messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps;

@end

NS_ASSUME_NONNULL_END
