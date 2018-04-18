//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkedDeviceReadReceipt.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkedDeviceReadReceipt ()

// FIXME remove this `timestamp` property and migrate in initWithCoder.
@property (nonatomic, readonly) uint64_t timestamp;

@end

@implementation OWSLinkedDeviceReadReceipt

- (instancetype)initWithSenderId:(NSString *)senderId
              messageIdTimestamp:(uint64_t)messageIdTimestamp
                   readTimestamp:(uint64_t)readTimestamp
{
    OWSAssert(senderId.length > 0 && messageIdTimestamp > 0);

    NSString *receiptId =
        [OWSLinkedDeviceReadReceipt uniqueIdForSenderId:senderId messageIdTimestamp:messageIdTimestamp];
    self = [super initWithUniqueId:receiptId];
    if (!self) {
        return self;
    }

    _senderId = senderId;
    _messageIdTimestamp = messageIdTimestamp;
    _readTimestamp = readTimestamp;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (!_messageIdTimestamp) {
        // FIXME to remove this legacy `timestamp` property, we need to figure out exactly how MTL encodes uint64_t.
        // e.g. can we just do something like: `((NSNumber *)[coder decodeObjectForKey:@"timestamp"]).unsignedLongLong`
        _messageIdTimestamp = _timestamp;
    }

    // For legacy early LinkedDeviceReadReceipts, before we were tracking read time, we assume the message was read as
    // soon as it was sent. This is always going to be at least a little earlier than it was actually read, but we have
    // nothing better to choose, and by the very fact that we're receiving a read receipt, we have good reason to
    // believe they read the message on the other device.
    if (_readTimestamp == 0) {
        _readTimestamp = _timestamp;
    }

    return self;
}

+ (NSString *)uniqueIdForSenderId:(NSString *)senderId messageIdTimestamp:(uint64_t)messageIdTimestamp
{
    OWSAssert(senderId.length > 0 && messageIdTimestamp > 0);

    return [NSString stringWithFormat:@"%@-%llu", senderId, messageIdTimestamp];
}

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithSenderId:(NSString *)senderId
                                                              messageIdTimestamp:(uint64_t)messageIdTimestamp
                                                                     transaction:
                                                                         (YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);
    NSString *receiptId =
        [OWSLinkedDeviceReadReceipt uniqueIdForSenderId:senderId messageIdTimestamp:messageIdTimestamp];
    return [OWSLinkedDeviceReadReceipt fetchObjectWithUniqueID:receiptId transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
