//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSGroupModel.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kMaxEncryptedAvatarSize = 3 * 1024 * 1024;
const NSUInteger kMaxAvatarSize = (kMaxEncryptedAvatarSize
    /* The length of the padding. See GroupSecretParams:encrypt_blob_with_padding in LibSignal. */
    - sizeof(uint32_t)
    /* Overhead from GroupAttributeBlob (protobuf) via GroupV2Params.encryptGroupAvatar(_:). */
    /* One byte for "2:LEN" & 4 bytes to represent more than 2 MiB of data (2^21). */
    - 1
    - 4
    /* The padding bytes themselves. See ClientZkGroupCipher.encryptBlob(randomness:plaintext:). */
    - 0
    /* Encryption tag & nonce. See GroupSecretParams:encrypt_blob in LibSignal. */
    - 16
    - 12
    /* Reserved byte. See GroupSecretParams:encrypt_blob in LibSignal. */
    - 1);
const NSUInteger kGroupIdLengthV1 = 16;
const NSUInteger kGroupIdLengthV2 = 32;

NSUInteger const TSGroupModelSchemaVersion = 2;

@interface TSGroupModel ()

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupName = _groupName;

#if TARGET_OS_IOS

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                 addedByAddress:(nullable SignalServiceAddress *)addedByAddress
{
    self = [super init];
    if (!self) {
        return self;
    }

    _groupId = groupId;
    _groupName = name;
    _groupMembers = members;
    _addedByAddress = addedByAddress;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    if (avatarData) {
        NSError *error;
        [self persistAvatarData:avatarData error:&error];
        if (error) {
            OWSFailDebug(@"Failed to persist group avatar data %@", error);
        }
    }

    OWSAssertDebug([GroupManager isValidGroupId:groupId groupsVersion:self.groupsVersion]);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    SignalServiceAddress *addedByAddress = self.addedByAddress;
    if (addedByAddress != nil) {
        [coder encodeObject:addedByAddress forKey:@"addedByAddress"];
    }
    NSString *avatarHash = self.avatarHash;
    if (avatarHash != nil) {
        [coder encodeObject:avatarHash forKey:@"avatarHash"];
    }
    NSData *groupId = self.groupId;
    if (groupId != nil) {
        [coder encodeObject:groupId forKey:@"groupId"];
    }
    if (![self isKindOfClass:[TSGroupModelV2 class]]) {
        NSArray *groupMembers = self.groupMembers;
        if (groupMembers != nil) {
            [coder encodeObject:groupMembers forKey:@"groupMembers"];
        }
    }
    [coder encodeObject:[self valueForKey:@"groupModelSchemaVersion"] forKey:@"groupModelSchemaVersion"];
    NSString *groupName = self.groupName;
    if (groupName != nil) {
        [coder encodeObject:groupName forKey:@"groupName"];
    }
    NSData *legacyAvatarData = self.legacyAvatarData;
    if (legacyAvatarData != nil) {
        [coder encodeObject:legacyAvatarData forKey:@"legacyAvatarData"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_addedByAddress = [coder decodeObjectOfClass:[SignalServiceAddress class] forKey:@"addedByAddress"];
    self->_avatarHash = [coder decodeObjectOfClass:[NSString class] forKey:@"avatarHash"];
    self->_groupId = [coder decodeObjectOfClass:[NSData class] forKey:@"groupId"];
    self->_groupMembers =
        [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [SignalServiceAddress class] ]]
                              forKey:@"groupMembers"];
    self->_groupModelSchemaVersion =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                         forKey:@"groupModelSchemaVersion"] unsignedIntegerValue];
    self->_groupName = [coder decodeObjectOfClass:[NSString class] forKey:@"groupName"];
    self->_legacyAvatarData = [coder decodeObjectOfClass:[NSData class] forKey:@"legacyAvatarData"];

    OWSAssertDebug([GroupManager isValidGroupId:self.groupId groupsVersion:self.groupsVersion]);

    if (_groupModelSchemaVersion < 1) {
        NSArray<NSString *> *_Nullable memberE164s = [coder decodeObjectForKey:@"groupMemberIds"];
        if (memberE164s) {
            NSMutableArray<SignalServiceAddress *> *memberAddresses = [NSMutableArray new];
            for (NSString *phoneNumber in memberE164s) {
                [memberAddresses addObject:[SignalServiceAddress legacyAddressWithServiceIdString:nil
                                                                                      phoneNumber:phoneNumber]];
            }
            _groupMembers = [memberAddresses copy];
        } else {
            _groupMembers = @[];
        }
    }

    if (_groupModelSchemaVersion < 2) {
        _legacyAvatarData = [coder decodeObjectForKey:@"groupAvatarData"];
    }

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.addedByAddress.hash;
    result ^= self.avatarHash.hash;
    result ^= self.groupId.hash;
    result ^= self.groupMembers.hash;
    result ^= self.groupModelSchemaVersion;
    result ^= self.groupName.hash;
    result ^= self.legacyAvatarData.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSGroupModel *typedOther = (TSGroupModel *)other;
    if (![NSObject isObject:self.addedByAddress equalToObject:typedOther.addedByAddress]) {
        return NO;
    }
    if (![NSObject isObject:self.avatarHash equalToObject:typedOther.avatarHash]) {
        return NO;
    }
    if (![NSObject isObject:self.groupId equalToObject:typedOther.groupId]) {
        return NO;
    }
    if (![NSObject isObject:self.groupMembers equalToObject:typedOther.groupMembers]) {
        return NO;
    }
    if (self.groupModelSchemaVersion != typedOther.groupModelSchemaVersion) {
        return NO;
    }
    if (![NSObject isObject:self.groupName equalToObject:typedOther.groupName]) {
        return NO;
    }
    if (![NSObject isObject:self.legacyAvatarData equalToObject:typedOther.legacyAvatarData]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSGroupModel *result = [[[self class] allocWithZone:zone] init];
    result->_addedByAddress = self.addedByAddress;
    result->_avatarHash = self.avatarHash;
    result->_groupId = self.groupId;
    result->_groupMembers = self.groupMembers;
    result->_groupModelSchemaVersion = self.groupModelSchemaVersion;
    result->_groupName = self.groupName;
    result->_legacyAvatarData = self.legacyAvatarData;
    return result;
}

- (GroupsVersion)groupsVersion
{
    return GroupsVersionV1;
}

- (GroupMembership *)groupMembership
{
    return [[GroupMembership alloc] initWithV1Members:self.groupMembers];
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = [self.groupName filterStringForDisplay];
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

@end

NS_ASSUME_NONNULL_END
