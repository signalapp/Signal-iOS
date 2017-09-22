//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSReadReceipt;

@interface OWSReadReceiptsForSenderMessage : TSOutgoingMessage

- (instancetype)initWithThread:(nullable TSThread *)thread messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps;

@end

NS_ASSUME_NONNULL_END
