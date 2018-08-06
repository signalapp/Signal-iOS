//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkedDeviceReadReceipt : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *senderId;
@property (nonatomic, readonly) uint64_t messageIdTimestamp;
@property (nonatomic, readonly) uint64_t readTimestamp;

- (instancetype)initWithSenderId:(NSString *)senderId
              messageIdTimestamp:(uint64_t)messageIdtimestamp
                   readTimestamp:(uint64_t)readTimestamp;

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithSenderId:(NSString *)senderId
                                                              messageIdTimestamp:(uint64_t)messageIdTimestamp
                                                                     transaction:
                                                                         (YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
