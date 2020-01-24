//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class GroupAccess;
@class SignalServiceAddress;

extern const int32_t kGroupIdLengthV1;
extern const int32_t kGroupIdLengthV2;

typedef NS_CLOSED_ENUM(uint32_t, GroupsVersion) { GroupsVersionV1 = 0, GroupsVersionV2 };

typedef NS_CLOSED_ENUM(NSUInteger, TSGroupMemberRole) { TSGroupMemberRole_Normal = 0, TSGroupMemberRole_Administrator };

// NOTE: This class is tightly coupled to GroupManager.
//       If you modify this class - especially if you
//       add any new properties - make sure to update
//       GroupManager.buildGroupModel().
@interface TSGroupModel : MTLModel

// groupMembers includes administrators and normal members.
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *groupMembers;
// The contents of groupMembers, excluding the local user.
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *nonLocalGroupMembers;
@property (nonatomic, readonly, nullable) NSString *groupName;
@property (nonatomic, readonly) NSData *groupId;

#if TARGET_OS_IOS
@property (nonatomic, readonly, nullable) UIImage *groupAvatarImage;
// This data should always be in PNG format.
@property (nonatomic, readonly, nullable) NSData *groupAvatarData;

@property (nonatomic, readonly) GroupsVersion groupsVersion;

// These properties only apply if groupsVersion == GroupsVersionV2.
@property (nonatomic, readonly, nullable) NSData *groupSecretParamsData;
@property (nonatomic, readonly) uint32_t groupV2Revision;
// Note that this property uses TSGroupMemberRole, not GroupsProtoMemberRole.
@property (nonatomic, readonly, nullable) NSDictionary<NSUUID *, NSNumber *> *groupsV2MemberRoles;
// Note that this property uses TSGroupMemberRole, not GroupsProtoMemberRole.
@property (nonatomic, readonly, nullable) NSDictionary<NSUUID *, NSNumber *> *groupsV2PendingMemberRoles;
@property (nonatomic, readonly, nullable) GroupAccess *groupAccess;

// GroupsV2 TODO: This should be done via GroupManager.
- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image;

// GroupsV2 TODO: This should be done via GroupManager.
- (void)updateGroupMembers:(NSArray<SignalServiceAddress *> *)groupMembers;

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
            groupsV2MemberRoles:(NSDictionary<NSUUID *, NSNumber *> *)groupsV2MemberRoles
     groupsV2PendingMemberRoles:(NSDictionary<NSUUID *, NSNumber *> *)groupsV2PendingMemberRoles
                    groupAccess:(GroupAccess *)groupAccess
                  groupsVersion:(GroupsVersion)groupsVersion
                groupV2Revision:(uint32_t)groupV2Revision
          groupSecretParamsData:(nullable NSData *)groupSecretParamsData NS_DESIGNATED_INITIALIZER;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

+ (NSData *)generateRandomV1GroupId;

// Note that these methods use TSGroupMemberRole, not GroupsProtoMemberRole.
//
// Generally it should be more convenient to use groupMembership rather than
// these properties.
- (TSGroupMemberRole)roleForGroupsV2Member:(SignalServiceAddress *)address;
- (TSGroupMemberRole)roleForGroupsV2PendingMember:(SignalServiceAddress *)address;

@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *administrators;
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *pendingNormalMembers;
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *pendingAdministrators;

@end

NS_ASSUME_NONNULL_END
