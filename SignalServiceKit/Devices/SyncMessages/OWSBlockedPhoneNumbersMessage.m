//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;
@property (nonatomic, readonly) NSArray<NSString *> *uuids;
@property (nonatomic, readonly) NSArray<NSData *> *groupIds;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSArray *groupIds = self.groupIds;
    if (groupIds != nil) {
        [coder encodeObject:groupIds forKey:@"groupIds"];
    }
    NSArray *phoneNumbers = self.phoneNumbers;
    if (phoneNumbers != nil) {
        [coder encodeObject:phoneNumbers forKey:@"phoneNumbers"];
    }
    NSArray *uuids = self.uuids;
    if (uuids != nil) {
        [coder encodeObject:uuids forKey:@"uuids"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_groupIds = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSData class] ]]
                                            forKey:@"groupIds"];
    self->_phoneNumbers = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSString class] ]]
                                                forKey:@"phoneNumbers"];
    self->_uuids = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSUUID class] ]]
                                         forKey:@"uuids"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.groupIds.hash;
    result ^= self.phoneNumbers.hash;
    result ^= self.uuids.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSBlockedPhoneNumbersMessage *typedOther = (OWSBlockedPhoneNumbersMessage *)other;
    if (![NSObject isObject:self.groupIds equalToObject:typedOther.groupIds]) {
        return NO;
    }
    if (![NSObject isObject:self.phoneNumbers equalToObject:typedOther.phoneNumbers]) {
        return NO;
    }
    if (![NSObject isObject:self.uuids equalToObject:typedOther.uuids]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSBlockedPhoneNumbersMessage *result = [super copyWithZone:zone];
    result->_groupIds = self.groupIds;
    result->_phoneNumbers = self.phoneNumbers;
    result->_uuids = self.uuids;
    return result;
}

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                       phoneNumbers:(NSArray<NSString *> *)phoneNumbers
                         aciStrings:(NSArray<NSString *> *)aciStrings
                           groupIds:(NSArray<NSData *> *)groupIds
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];
    _uuids = [aciStrings copy];
    _groupIds = [groupIds copy];

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageBlockedBuilder *blockedBuilder = [SSKProtoSyncMessageBlocked builder];
    [blockedBuilder setNumbers:_phoneNumbers];
    if (BuildFlagsObjC.serviceIdStrings) {
        [blockedBuilder setAcis:_uuids];
    }
    NSMutableArray<NSData *> *aciBinaries = [NSMutableArray array];
    for (NSString *aciString in _uuids) {
        AciObjC *aciObj = [[AciObjC alloc] initWithAciString:aciString];
        if (aciObj != nil) {
            [aciBinaries addObject:aciObj.serviceIdBinary];
        }
    }
    if (BuildFlagsObjC.serviceIdBinaryVariableOverhead) {
        [blockedBuilder setAcisBinary:aciBinaries];
    }
    [blockedBuilder setGroupIds:_groupIds];

    SSKProtoSyncMessageBlocked *blockedProto = [blockedBuilder buildInfallibly];

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setBlocked:blockedProto];
    return syncMessageBuilder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
