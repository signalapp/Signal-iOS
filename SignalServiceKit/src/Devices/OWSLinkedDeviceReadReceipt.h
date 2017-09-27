//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkedDeviceReadReceipt : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *senderId;
@property (nonatomic, readonly) uint64_t timestamp;

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithSenderId:(NSString *)senderId
                                                                       timestamp:(uint64_t)timestamp
                                                                     transaction:
                                                                         (YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
