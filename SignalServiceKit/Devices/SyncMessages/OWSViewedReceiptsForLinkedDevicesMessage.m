//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSViewedReceiptsForLinkedDevicesMessage.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewedReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceViewedReceipt *> *viewedReceipts;

@end

@implementation OWSViewedReceiptsForLinkedDevicesMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                     viewedReceipts:(NSArray<OWSLinkedDeviceViewedReceipt *> *)viewedReceipts
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return self;
    }

    _viewedReceipts = [viewedReceipts copy];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSArray *viewedReceipts = self.viewedReceipts;
    if (viewedReceipts != nil) {
        [coder encodeObject:viewedReceipts forKey:@"viewedReceipts"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_viewedReceipts =
        [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [OWSLinkedDeviceViewedReceipt class] ]]
                              forKey:@"viewedReceipts"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.viewedReceipts.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSViewedReceiptsForLinkedDevicesMessage *typedOther = (OWSViewedReceiptsForLinkedDevicesMessage *)other;
    if (![NSObject isObject:self.viewedReceipts equalToObject:typedOther.viewedReceipts]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSViewedReceiptsForLinkedDevicesMessage *result = [super copyWithZone:zone];
    result->_viewedReceipts = self.viewedReceipts;
    return result;
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    for (OWSLinkedDeviceViewedReceipt *viewedReceipt in self.viewedReceipts) {
        SSKProtoSyncMessageViewedBuilder *viewedProtoBuilder =
            [SSKProtoSyncMessageViewed builderWithTimestamp:viewedReceipt.messageIdTimestamp];

        ServiceIdObjC *aciObj = viewedReceipt.senderAddress.serviceIdObjC;
        if ([aciObj isKindOfClass:[AciObjC class]]) {
            if (BuildFlagsObjC.serviceIdStrings) {
                [viewedProtoBuilder setSenderAci:aciObj.serviceIdString];
            }
            if (BuildFlagsObjC.serviceIdBinaryVariableOverhead) {
                [viewedProtoBuilder setSenderAciBinary:aciObj.serviceIdBinary];
            }
        } else {
            OWSFailDebug(@"can't send viewed receipt for message without an ACI");
        }

        NSError *error;
        SSKProtoSyncMessageViewed *_Nullable viewedProto = [viewedProtoBuilder buildAndReturnError:&error];
        if (error || !viewedProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [syncMessageBuilder addViewed:viewedProto];
    }
    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    NSMutableArray<NSString *> *messageUniqueIds = [[NSMutableArray alloc] init];
    for (OWSLinkedDeviceViewedReceipt *viewReceipt in self.viewedReceipts) {
        if (viewReceipt.messageUniqueId) {
            [messageUniqueIds addObject:viewReceipt.messageUniqueId];
        }
    }
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:messageUniqueIds];
}

@end

@interface OWSLinkedDeviceViewedReceipt ()

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;

@end

@implementation OWSLinkedDeviceViewedReceipt

- (instancetype)initWithSenderAci:(AciObjC *)senderAci
                  messageUniqueId:(nullable NSString *)messageUniqueId
               messageIdTimestamp:(uint64_t)messageIdTimestamp
                  viewedTimestamp:(uint64_t)viewedTimestamp
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
    _viewedTimestamp = viewedTimestamp;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:[self valueForKey:@"messageIdTimestamp"] forKey:@"messageIdTimestamp"];
    NSString *messageUniqueId = self.messageUniqueId;
    if (messageUniqueId != nil) {
        [coder encodeObject:messageUniqueId forKey:@"messageUniqueId"];
    }
    NSString *senderPhoneNumber = self.senderPhoneNumber;
    if (senderPhoneNumber != nil) {
        [coder encodeObject:senderPhoneNumber forKey:@"senderPhoneNumber"];
    }
    NSString *senderUUID = self.senderUUID;
    if (senderUUID != nil) {
        [coder encodeObject:senderUUID forKey:@"senderUUID"];
    }
    [coder encodeObject:[self valueForKey:@"viewedTimestamp"] forKey:@"viewedTimestamp"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_messageIdTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"messageIdTimestamp"] unsignedLongLongValue];
    self->_messageUniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"messageUniqueId"];
    self->_senderPhoneNumber = [coder decodeObjectOfClass:[NSString class] forKey:@"senderPhoneNumber"];
    self->_senderUUID = [coder decodeObjectOfClass:[NSString class] forKey:@"senderUUID"];
    self->_viewedTimestamp = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                              forKey:@"viewedTimestamp"] unsignedLongLongValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.messageIdTimestamp;
    result ^= self.messageUniqueId.hash;
    result ^= self.senderPhoneNumber.hash;
    result ^= self.senderUUID.hash;
    result ^= self.viewedTimestamp;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    OWSLinkedDeviceViewedReceipt *typedOther = (OWSLinkedDeviceViewedReceipt *)other;
    if (self.messageIdTimestamp != typedOther.messageIdTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueId equalToObject:typedOther.messageUniqueId]) {
        return NO;
    }
    if (![NSObject isObject:self.senderPhoneNumber equalToObject:typedOther.senderPhoneNumber]) {
        return NO;
    }
    if (![NSObject isObject:self.senderUUID equalToObject:typedOther.senderUUID]) {
        return NO;
    }
    if (self.viewedTimestamp != typedOther.viewedTimestamp) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSLinkedDeviceViewedReceipt *result = [[[self class] allocWithZone:zone] init];
    result->_messageIdTimestamp = self.messageIdTimestamp;
    result->_messageUniqueId = self.messageUniqueId;
    result->_senderPhoneNumber = self.senderPhoneNumber;
    result->_senderUUID = self.senderUUID;
    result->_viewedTimestamp = self.viewedTimestamp;
    return result;
}

- (SignalServiceAddress *)senderAddress
{
    return [SignalServiceAddress legacyAddressWithServiceIdString:self.senderUUID phoneNumber:self.senderPhoneNumber];
}

@end

NS_ASSUME_NONNULL_END
