//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkedDeviceReadReceipt.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLinkedDeviceReadReceipt

- (instancetype)initWithSenderId:(NSString *)senderId
              messageIdTimestamp:(uint64_t)messageIdTimestamp
                   readTimestamp:(uint64_t)readTimestamp
{
    OWSAssertDebug(senderId.length > 0 && messageIdTimestamp > 0);

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

    // renamed timestamp -> messageIdTimestamp
    if (!_messageIdTimestamp) {
        NSNumber *_Nullable legacyTimestamp = (NSNumber *)[coder decodeObjectForKey:@"timestamp"];
        OWSAssertDebug(legacyTimestamp.unsignedLongLongValue > 0);
        _messageIdTimestamp = legacyTimestamp.unsignedLongLongValue;
    }

    // For legacy objects, before we were tracking read time, use the original messages "sent" timestamp
    // as the local read time. This will always be at least a little bit earlier than the message was
    // actually read, which isn't ideal, but safer than persisting a disappearing message too long, especially
    // since we know they read it on their linked desktop.
    if (_readTimestamp == 0) {
        _readTimestamp = _messageIdTimestamp;
    }

    return self;
}

+ (NSString *)uniqueIdForSenderId:(NSString *)senderId messageIdTimestamp:(uint64_t)messageIdTimestamp
{
    OWSAssertDebug(senderId.length > 0 && messageIdTimestamp > 0);

    return [NSString stringWithFormat:@"%@-%llu", senderId, messageIdTimestamp];
}

+ (nullable OWSLinkedDeviceReadReceipt *)findLinkedDeviceReadReceiptWithSenderId:(NSString *)senderId
                                                              messageIdTimestamp:(uint64_t)messageIdTimestamp
                                                                     transaction:
                                                                         (YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    NSString *receiptId =
        [OWSLinkedDeviceReadReceipt uniqueIdForSenderId:senderId messageIdTimestamp:messageIdTimestamp];
    return [OWSLinkedDeviceReadReceipt fetchObjectWithUniqueID:receiptId transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
