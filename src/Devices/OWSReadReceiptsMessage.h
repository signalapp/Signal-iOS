//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSReadReceipt;

@interface OWSReadReceiptsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts;

@end

NS_ASSUME_NONNULL_END