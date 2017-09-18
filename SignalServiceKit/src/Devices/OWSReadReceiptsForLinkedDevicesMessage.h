//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSReadReceipt;

@interface OWSReadReceiptsForLinkedDevicesMessage : OWSOutgoingSyncMessage

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts;

@end

NS_ASSUME_NONNULL_END
