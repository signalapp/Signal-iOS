//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class GroupAccess;
@class GroupMembership;
@class SignalServiceAddress;

extern const int32_t kGroupIdLengthV1;
extern const int32_t kGroupIdLengthV2;

typedef NS_CLOSED_ENUM(uint32_t, GroupsVersion) { GroupsVersionV1 = 0, GroupsVersionV2 };

typedef NS_CLOSED_ENUM(
    NSUInteger, TSGroupMemberRole) { TSGroupMemberRole_Normal = 0, TSGroupMemberRole_Administrator = 1 };

typedef NS_CLOSED_ENUM(NSUInteger, TSGroupModelComparisonMode) {
    TSGroupModelComparisonMode_CompareAll,
    TSGroupModelComparisonMode_UserFacingOnly,
};

// NOTE: This class is tightly coupled to TSGroupModelBuilder.
//       If you modify this class - especially if you
//       add any new properties - make sure to update
//       TSGroupModelBuilder.
@interface TSGroupModel : MTLModel

// groupMembers includes administrators and normal members.
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *groupMembers;
// The contents of groupMembers, excluding the local user.
@property (nonatomic, readonly) NSArray<SignalServiceAddress *> *nonLocalGroupMembers;
@property (nonatomic, readonly, nullable) NSString *groupName;
@property (nonatomic, readonly) NSData *groupId;
@property (nonatomic, readonly, nullable) SignalServiceAddress *addedByAddress;

#if TARGET_OS_IOS
@property (nonatomic, readonly, nullable) UIImage *groupAvatarImage;
// This data should always be in PNG format.
@property (nonatomic, readonly, nullable) NSData *groupAvatarData;

@property (nonatomic, readonly) GroupsVersion groupsVersion;
@property (nonatomic, readonly) GroupMembership *groupMembership;

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                 addedByAddress:(nullable SignalServiceAddress *)addedByAddress NS_DESIGNATED_INITIALIZER;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model comparisonMode:(TSGroupModelComparisonMode)comparisonMode;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

+ (NSData *)generateRandomV1GroupId;

@end

NS_ASSUME_NONNULL_END
