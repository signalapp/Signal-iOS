//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSViewOnceMessageReadSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewOnceMessageReadSyncMessage ()
@property (nonatomic, readonly, nullable) NSString *messageUniqueId; // Only nil if decoding old values
@end

@implementation OWSViewOnceMessageReadSyncMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                          senderAci:(AciObjC *)senderAci
                            message:(TSMessage *)message
                      readTimestamp:(uint64_t)readTimestamp
                        transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(message.timestamp > 0);

    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return self;
    }

    _senderAddress = [[SignalServiceAddress alloc] initWithServiceIdObjC:senderAci];
    _messageUniqueId = message.uniqueId;
    _messageIdTimestamp = message.timestamp;
    _readTimestamp = readTimestamp;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:[self valueForKey:@"messageIdTimestamp"] forKey:@"messageIdTimestamp"];
    NSString *messageUniqueId = self.messageUniqueId;
    if (messageUniqueId != nil) {
        [coder encodeObject:messageUniqueId forKey:@"messageUniqueId"];
    }
    [coder encodeObject:[self valueForKey:@"readTimestamp"] forKey:@"readTimestamp"];
    SignalServiceAddress *senderAddress = self.senderAddress;
    if (senderAddress != nil) {
        [coder encodeObject:senderAddress forKey:@"senderAddress"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_messageIdTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"messageIdTimestamp"] unsignedLongLongValue];
    self->_messageUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"messageUniqueId"];
    self->_readTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                            forKey:@"readTimestamp"] unsignedLongLongValue];
    self->_senderAddress = [coder decodeObjectOfClass:[SignalServiceAddress class] forKey:@"senderAddress"];

    if (_senderAddress == nil) {
        NSString *phoneNumber = [coder decodeObjectForKey:@"senderId"];
        _senderAddress = [SignalServiceAddress legacyAddressWithServiceIdString:nil phoneNumber:phoneNumber];
        OWSAssertDebug(_senderAddress.isValid);
    }

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.messageIdTimestamp;
    result ^= self.messageUniqueId.hash;
    result ^= self.readTimestamp;
    result ^= self.senderAddress.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSViewOnceMessageReadSyncMessage *typedOther = (OWSViewOnceMessageReadSyncMessage *)other;
    if (self.messageIdTimestamp != typedOther.messageIdTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueId equalToObject:typedOther.messageUniqueId]) {
        return NO;
    }
    if (self.readTimestamp != typedOther.readTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.senderAddress equalToObject:typedOther.senderAddress]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSViewOnceMessageReadSyncMessage *result = [super copyWithZone:zone];
    result->_messageIdTimestamp = self.messageIdTimestamp;
    result->_messageUniqueId = self.messageUniqueId;
    result->_readTimestamp = self.readTimestamp;
    result->_senderAddress = self.senderAddress;
    return result;
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    SSKProtoSyncMessageViewOnceOpenBuilder *readProtoBuilder =
        [SSKProtoSyncMessageViewOnceOpen builderWithTimestamp:self.messageIdTimestamp];
    ServiceIdObjC *senderAci = self.senderAddress.serviceIdObjC;
    if ([senderAci isKindOfClass:[AciObjC class]]) {
        if (BuildFlagsObjC.serviceIdStrings) {
            readProtoBuilder.senderAci = senderAci.serviceIdString;
        }
        if (BuildFlagsObjC.serviceIdBinaryConstantOverhead) {
            readProtoBuilder.senderAciBinary = senderAci.serviceIdBinary;
        }
    } else {
        OWSFailDebug(@"can't send view once open sync for message without an ACI");
    }
    NSError *error;
    SSKProtoSyncMessageViewOnceOpen *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
    if (error || !readProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    [syncMessageBuilder setViewOnceOpen:readProto];

    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    if (self.messageUniqueId) {
        return [[super relatedUniqueIds] setByAddingObject:self.messageUniqueId];
    } else {
        return [super relatedUniqueIds];
    }
}

@end

NS_ASSUME_NONNULL_END
