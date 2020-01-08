//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

extern const int32_t kGroupIdLength;

typedef NS_CLOSED_ENUM(uint32_t, GroupsVersion) { GroupsVersionV1 = 0, GroupsVersionV2 };

typedef NS_CLOSED_ENUM(NSUInteger, TSGroupMemberRole) { TSGroupMemberRole_Normal = 0, TSGroupMemberRole_Administrator };

@interface TSGroupModel : MTLModel

@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *groupMembers;
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *externalGroupMembers;
@property (nonatomic, readonly, nullable) NSString *groupName;
@property (nonatomic, readonly) NSData *groupId;

#if TARGET_OS_IOS
@property (nonatomic, readonly, nullable) UIImage *groupAvatarImage;
// This data should always be in PNG format.
@property (nonatomic, readonly, nullable) NSData *groupAvatarData;

@property (nonatomic, readonly) GroupsVersion groupsVersion;
@property (nonatomic, readonly, nullable) NSData *groupSecretParamsData;
@property (nonatomic, readonly) uint32_t groupV2Revision;
@property (nonatomic, readonly, nullable) NSMutableDictionary<NSString *, NSNumber *> *groupsV2MemberRoles;

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
                 administrators:(NSArray<SignalServiceAddress *> *)administrators
                  groupsVersion:(GroupsVersion)groupsVersion
          groupSecretParamsData:(nullable NSData *)groupSecretParamsData NS_DESIGNATED_INITIALIZER;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

+ (NSData *)generateRandomGroupId;

// Note that this method uses TSGroupMemberRole, not GroupsProtoMemberRole.
- (TSGroupMemberRole)roleForGroupsV2Member:(SignalServiceAddress *)address;

// Note that this method uses TSGroupMemberRole, not GroupsProtoMemberRole.
//
// This method should only be called by GroupManager.
- (void)setRoleForGroupsV2Member:(SignalServiceAddress *)address role:(TSGroupMemberRole)role;

- (BOOL)isAdministrator:(SignalServiceAddress *)address;

@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *administrators;

@end

NS_ASSUME_NONNULL_END
