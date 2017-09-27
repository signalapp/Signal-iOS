//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkedDeviceReadReceipt.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLinkedDeviceReadReceipt

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;
{
    OWSAssert(senderId.length > 0 && timestamp > 0);

    self = [super initWithUniqueId:[OWSLinkedDeviceReadReceipt uniqueIdForSenderId:senderId timestamp:timestamp]];
    if (!self) {
        return self;
    }

    _senderId = senderId;
    _timestamp = timestamp;

    return self;
}

+ (NSString *)uniqueIdForSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp
{
    OWSAssert(senderId.length > 0 && timestamp > 0);

    return [NSString stringWithFormat:@"%@-%llu", senderId, timestamp];
}

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithSenderId:(NSString *)senderId
                                                                       timestamp:(uint64_t)timestamp
                                                                     transaction:
                                                                         (YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);

    return [OWSLinkedDeviceReadReceipt fetchObjectWithUniqueID:[self uniqueIdForSenderId:senderId timestamp:timestamp]
                                                   transaction:transaction];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
