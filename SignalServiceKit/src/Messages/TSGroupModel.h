//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

extern const int32_t kGroupIdLength;

@interface TSGroupModel : MTLModel

@property (nonatomic) NSArray<SignalServiceAddress *> *groupMembers;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;

#if TARGET_OS_IOS
@property (nullable, nonatomic, readonly) UIImage *groupAvatarImage;
// This data should always be in PNG format.
@property (nullable, nonatomic) NSData *groupAvatarData;

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image;

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image;

- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
             groupAvatarImage:(nullable UIImage *)groupAvatarImage
                      groupId:(NSData *)groupId;

- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
              groupAvatarData:(nullable NSData *)groupAvatarData
                      groupId:(NSData *)groupId;

- (instancetype)initWithGroupId:(NSData *)groupId
                   groupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
                      groupName:(nullable NSString *)groupName;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@property (nonatomic, readonly) NSString *groupNameOrDefault;

@end

NS_ASSUME_NONNULL_END
