//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSLinkedDeviceReadReceipt.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger const OWSLinkedDeviceReadReceiptSchemaVersion = 1;

@interface OWSLinkedDeviceReadReceipt ()

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;
@property (nonatomic, readonly) NSUInteger linkedDeviceReadReceiptSchemaVersion;

@end

@implementation OWSLinkedDeviceReadReceipt

- (instancetype)initWithSenderAci:(AciObjC *)senderAci
                  messageUniqueId:(nullable NSString *)messageUniqueId
               messageIdTimestamp:(uint64_t)messageIdTimestamp
                    readTimestamp:(uint64_t)readTimestamp
{
    OWSAssertDebug(messageIdTimestamp > 0);

    self = [super init];
    if (!self) {
        return self;
    }

    _senderPhoneNumber = nil;
    _senderUUID = senderAci.serviceIdUppercaseString;
    _messageUniqueId = messageUniqueId;
    _messageIdTimestamp = messageIdTimestamp;
    _readTimestamp = readTimestamp;
    _linkedDeviceReadReceiptSchemaVersion = OWSLinkedDeviceReadReceiptSchemaVersion;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self valueForKey:@"linkedDeviceReadReceiptSchemaVersion"]
                 forKey:@"linkedDeviceReadReceiptSchemaVersion"];
    [coder encodeObject:[self valueForKey:@"messageIdTimestamp"] forKey:@"messageIdTimestamp"];
    NSString *messageUniqueId = self.messageUniqueId;
    if (messageUniqueId != nil) {
        [coder encodeObject:messageUniqueId forKey:@"messageUniqueId"];
    }
    [coder encodeObject:[self valueForKey:@"readTimestamp"] forKey:@"readTimestamp"];
    NSString *senderPhoneNumber = self.senderPhoneNumber;
    if (senderPhoneNumber != nil) {
        [coder encodeObject:senderPhoneNumber forKey:@"senderPhoneNumber"];
    }
    NSString *senderUUID = self.senderUUID;
    if (senderUUID != nil) {
        [coder encodeObject:senderUUID forKey:@"senderUUID"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_linkedDeviceReadReceiptSchemaVersion =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                         forKey:@"linkedDeviceReadReceiptSchemaVersion"] unsignedIntegerValue];
    self->_messageIdTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"messageIdTimestamp"] unsignedLongLongValue];
    self->_messageUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"messageUniqueId"];
    self->_readTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                            forKey:@"readTimestamp"] unsignedLongLongValue];
    self->_senderPhoneNumber = [coder decodeObjectOfClass:[NSString class] forKey:@"senderPhoneNumber"];
    self->_senderUUID = [coder decodeObjectOfClass:[NSString class] forKey:@"senderUUID"];

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

    if (_linkedDeviceReadReceiptSchemaVersion < 1) {
        _senderPhoneNumber = [coder decodeObjectForKey:@"senderId"];
        OWSAssertDebug(_senderPhoneNumber);
    }

    _linkedDeviceReadReceiptSchemaVersion = OWSLinkedDeviceReadReceiptSchemaVersion;

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.linkedDeviceReadReceiptSchemaVersion;
    result ^= self.messageIdTimestamp;
    result ^= self.messageUniqueId.hash;
    result ^= self.readTimestamp;
    result ^= self.senderPhoneNumber.hash;
    result ^= self.senderUUID.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    OWSLinkedDeviceReadReceipt *typedOther = (OWSLinkedDeviceReadReceipt *)other;
    if (self.linkedDeviceReadReceiptSchemaVersion != typedOther.linkedDeviceReadReceiptSchemaVersion) {
        return NO;
    }
    if (self.messageIdTimestamp != typedOther.messageIdTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueId equalToObject:typedOther.messageUniqueId]) {
        return NO;
    }
    if (self.readTimestamp != typedOther.readTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.senderPhoneNumber equalToObject:typedOther.senderPhoneNumber]) {
        return NO;
    }
    if (![NSObject isObject:self.senderUUID equalToObject:typedOther.senderUUID]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSLinkedDeviceReadReceipt *result = [[[self class] allocWithZone:zone] init];
    result->_linkedDeviceReadReceiptSchemaVersion = self.linkedDeviceReadReceiptSchemaVersion;
    result->_messageIdTimestamp = self.messageIdTimestamp;
    result->_messageUniqueId = self.messageUniqueId;
    result->_readTimestamp = self.readTimestamp;
    result->_senderPhoneNumber = self.senderPhoneNumber;
    result->_senderUUID = self.senderUUID;
    return result;
}

- (SignalServiceAddress *)senderAddress
{
    return [SignalServiceAddress legacyAddressWithServiceIdString:self.senderUUID phoneNumber:self.senderPhoneNumber];
}

@end

NS_ASSUME_NONNULL_END
