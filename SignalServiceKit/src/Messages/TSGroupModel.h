//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

extern const int32_t kGroupIdLength;

typedef NS_CLOSED_ENUM(NSUInteger, GroupsVersion) { GroupsVersionV1 = 0, GroupsVersionV2 };

@interface TSGroupModel : MTLModel

@property (nonatomic) NSArray<SignalServiceAddress *> *groupMembers;
@property (nonatomic) NSArray<SignalServiceAddress *> *externalGroupMembers;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;

#if TARGET_OS_IOS
@property (nullable, nonatomic, readonly) UIImage *groupAvatarImage;
// This data should always be in PNG format.
@property (nullable, nonatomic) NSData *groupAvatarData;

@property (nonatomic) GroupsVersion groupsVersion;

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image;

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                  groupsVersion:(GroupsVersion)groupsVersion NS_DESIGNATED_INITIALIZER;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

+ (NSData *)generateRandomGroupId;

@end

NS_ASSUME_NONNULL_END
