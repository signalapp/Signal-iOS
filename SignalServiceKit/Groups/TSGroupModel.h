//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class GroupAccess;
@class GroupMembership;
@class SignalServiceAddress;

extern const NSUInteger kGroupIdLengthV1;
extern const NSUInteger kGroupIdLengthV2;
extern const NSUInteger kMaxEncryptedAvatarSize;
extern const NSUInteger kMaxAvatarSize;

typedef NS_CLOSED_ENUM(uint32_t, GroupsVersion) {
    GroupsVersionV1 = 0,
    GroupsVersionV2
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
// This data should always be in PNG format.
@property (nonatomic, nullable) NSData *legacyAvatarData;
@property (nonatomic, nullable) NSString *avatarHash;

@property (nonatomic, readonly) GroupsVersion groupsVersion;
@property (nonatomic, readonly) GroupMembership *groupMembership;

+ (BOOL)isValidGroupAvatarData:(nullable NSData *)imageData;
+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                 addedByAddress:(nullable SignalServiceAddress *)addedByAddress NS_DESIGNATED_INITIALIZER;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

+ (NSData *)generateRandomV1GroupId;

@end

NS_ASSUME_NONNULL_END
