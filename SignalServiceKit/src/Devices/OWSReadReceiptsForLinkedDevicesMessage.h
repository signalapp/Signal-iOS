//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSLinkedDeviceReadReceipt;

@interface OWSReadReceiptsForLinkedDevicesMessage : OWSOutgoingSyncMessage

- (instancetype)initWithReadReceipts:(NSArray<OWSLinkedDeviceReadReceipt *> *)readReceipts;

@end

NS_ASSUME_NONNULL_END
