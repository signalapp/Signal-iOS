//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "UIImage+OWS.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLengthV1 = 16;
const int32_t kGroupIdLengthV2 = 32;

NSUInteger const TSGroupModelSchemaVersion = 1;

@interface TSGroupModel ()

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@property (nonatomic) uint32_t groupV2Revision;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupName = _groupName;

#if TARGET_OS_IOS

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                 administrators:(NSArray<SignalServiceAddress *> *)administrators
                  groupsVersion:(GroupsVersion)groupsVersion
          groupSecretParamsData:(nullable NSData *)groupSecretParamsData
{
    OWSAssertDebug(members != nil);
    OWSAssertDebug([GroupManager isValidGroupId:groupId groupsVersion:groupsVersion]);
    if (groupsVersion == GroupsVersionV1) {
        OWSAssertDebug(groupSecretParamsData == nil);
    } else {
        OWSAssertDebug(groupSecretParamsData.length > 0);
    }

    self = [super init];
    if (!self) {
        return self;
    }

    _groupName = name;
    _groupMembers = [members copy];
    _groupAvatarData = avatarData;
    _groupId = groupId;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;
    _groupsVersion = groupsVersion;
    _groupSecretParamsData = groupSecretParamsData;

    NSMutableDictionary<NSString *, NSNumber *> *groupsV2MemberRoles = [NSMutableDictionary new];
    if (groupsVersion != GroupsVersionV1) {
        NSSet<SignalServiceAddress *> *administratorsSet = [NSSet setWithArray:administrators];
        for (SignalServiceAddress *address in members) {
            NSUUID *_Nullable uuid = address.uuid;
            if (address.uuid == nil) {
                OWSLogVerbose(@"Address: %@", address);
                OWSFailDebug(@"Address is missing uuid.");
                continue;
            }
            BOOL isAdministrator = [administratorsSet containsObject:address];
            groupsV2MemberRoles[uuid.UUIDString]
                = (isAdministrator ? @(TSGroupMemberRole_Administrator) : @(TSGroupMemberRole_Normal));
        }
    }
    _groupsV2MemberRoles = [groupsV2MemberRoles copy];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    OWSAssertDebug([GroupManager isValidGroupId:self.groupId groupsVersion:self.groupsVersion]);

    if (_groupModelSchemaVersion < 1) {
        NSArray<NSString *> *_Nullable memberE164s = [coder decodeObjectForKey:@"groupMemberIds"];
        if (memberE164s) {
            NSMutableArray<SignalServiceAddress *> *memberAddresses = [NSMutableArray new];
            for (NSString *phoneNumber in memberE164s) {
                [memberAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
            }
            _groupMembers = [memberAddresses copy];
        } else {
            _groupMembers = @[];
        }
    }

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    if (self.groupAvatarData == nil) {
        UIImage *_Nullable groupImage = [coder decodeObjectForKey:@"groupImage"];
        if ([groupImage isKindOfClass:[UIImage class]]) {
            self.groupAvatarData = [TSGroupModel dataForGroupAvatar:groupImage];
        }
    }

    return self;
}

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image
{
    if (image == nil) {
        return nil;
    }
    const CGFloat kMaxDimension = 800;
    if (image.pixelWidth > kMaxDimension ||
        image.pixelHeight > kMaxDimension) {
        CGFloat thumbnailSizePixels = MIN(kMaxDimension, MIN(image.pixelWidth, image.pixelHeight));
        image = [image resizedImageToFillPixelSize:CGSizeMake(thumbnailSizePixels, thumbnailSizePixels)];

        if (image == nil ||
            image.pixelWidth > kMaxDimension ||
            image.pixelHeight > kMaxDimension) {
            OWSLogVerbose(@"Could not resize group avatar: %@",
                          NSStringFromCGSize(image.pixelSize));
            OWSFailDebug(@"Could not resize group avatar.");
            return nil;
        }
    }
    NSData *_Nullable data = UIImagePNGRepresentation(image);
    if (data.length < 1) {
        OWSFailDebug(@"Could not convert group avatar to PNG.");
        return nil;
    }
    // We should never hit this limit, given the max dimension above.
    const NSUInteger kMaxLength = 500 * 1000;
    if (data.length > kMaxLength) {
        OWSLogVerbose(@"Group avatar data length: %lu (%@)",
                      (unsigned long)data.length,
                      NSStringFromCGSize(image.pixelSize));
        OWSFailDebug(@"Group avatar data has invalid length.");
        return nil;
    }
    return data;
}

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image
{
    self.groupAvatarData = [TSGroupModel dataForGroupAvatar:image];
}

- (nullable UIImage *)groupAvatarImage
{
    return [UIImage imageWithData:self.groupAvatarData];
}

- (void)setGroupAvatarData:(nullable NSData *)groupAvatarData {
    if (_groupAvatarData.length > 0 && groupAvatarData.length < 1) {
        OWSFailDebug(@"We should never remove an avatar from a group with an avatar.");
        return;
    }
    _groupAvatarData = groupAvatarData;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other {
    if (self == other)
        return YES;
    if (![_groupId isEqualToData:other.groupId]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupName equalTo:other.groupName]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupAvatarData equalTo:other.groupAvatarData]) {
        return NO;
    }
    NSSet<SignalServiceAddress *> *myGroupMembersSet = [NSSet setWithArray:_groupMembers];
    NSSet<SignalServiceAddress *> *otherGroupMembersSet = [NSSet setWithArray:other.groupMembers];
    if (![myGroupMembersSet isEqualToSet:otherGroupMembersSet]) {
        return NO;
    }
    if (_groupsVersion != other.groupsVersion) {
        return NO;
    }
    if (_groupsVersion == GroupsVersionV2) {
        if (_groupV2Revision != other.groupV2Revision) {
            return NO;
        }
        if (![NSObject isNullableObject:self.groupSecretParamsData equalTo:other.groupSecretParamsData]) {
            return NO;
        }
        if (![NSObject isNullableObject:self.groupsV2MemberRoles equalTo:other.groupsV2MemberRoles]) {
            return NO;
        }
    }
    return YES;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = self.groupName;
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

+ (NSData *)generateRandomV1GroupId
{
    return [Randomness generateRandomBytes:kGroupIdLengthV1];
}

- (NSArray<SignalServiceAddress *> *)nonLocalGroupMembers
{
    return [self.groupMembers filter:^(SignalServiceAddress *groupMemberId) {
        return !groupMemberId.isLocalAddress;
    }];
}

- (TSGroupMemberRole)roleForGroupsV2Member:(SignalServiceAddress *)address
{
    TSGroupMemberRole defaultRole = TSGroupMemberRole_Normal;

    NSUUID *_Nullable uuid = address.uuid;
    if (address.uuid == nil) {
        OWSLogVerbose(@"Address: %@", address);
        OWSFailDebug(@"Address is missing uuid.");
        return defaultRole;
    }
    NSNumber *_Nullable nsRole = self.groupsV2MemberRoles[uuid.UUIDString];
    if (nsRole == nil) {
        OWSLogVerbose(@"Address: %@", address);
        if (self.groupsVersion == GroupsVersionV2) {
            OWSFailDebug(@"Address is missing role.");
        }
        return defaultRole;
    }
    return (TSGroupMemberRole)nsRole.unsignedIntegerValue;
}

- (void)setRoleForGroupsV2Member:(SignalServiceAddress *)address role:(TSGroupMemberRole)role
{
    NSUUID *_Nullable uuid = address.uuid;
    if (address.uuid == nil) {
        OWSLogVerbose(@"Address: %@", address);
        OWSFailDebug(@"Address is missing uuid.");
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *groupsV2MemberRoles;
    if (self.groupsV2MemberRoles == nil) {
        groupsV2MemberRoles = [NSMutableDictionary new];
    } else {
        groupsV2MemberRoles = [_groupsV2MemberRoles mutableCopy];
    }
    groupsV2MemberRoles[uuid.UUIDString] = @(role);
    _groupsV2MemberRoles = [groupsV2MemberRoles copy];
}

- (BOOL)isAdministrator:(SignalServiceAddress *)address
{
    return [self roleForGroupsV2Member:address] == TSGroupMemberRole_Administrator;
}

// GroupsV2 TODO: This should be done via GroupManager.
- (void)updateGroupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
{
    _groupMembers = [groupMembers copy];
    // GroupsV2 TODO: Remove stale keys from groupsV2MemberRoles.
}

- (NSArray<SignalServiceAddress *> *)administrators
{
    if (self.groupsVersion == GroupsVersionV1) {
        return @[];
    }
    NSMutableArray<SignalServiceAddress *> *administrators = [NSMutableArray new];
    for (SignalServiceAddress *address in self.groupMembers) {
        if ([self isAdministrator:address]) {
            [administrators addObject:address];
        }
    }
    return administrators;
}

@end

NS_ASSUME_NONNULL_END
