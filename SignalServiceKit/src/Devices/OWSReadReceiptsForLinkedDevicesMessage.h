//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSLinkedDeviceReadReceipt;

@interface OWSReadReceiptsForLinkedDevicesMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithReadReceipts:(NSArray<OWSLinkedDeviceReadReceipt *> *)readReceipts NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
