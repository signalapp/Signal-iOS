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
@property (nonatomic, readonly) NSArray<NSString *> *transitional_groupMemberPhoneNumbers;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;

#if TARGET_OS_IOS
@property (nullable, nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId;

- (instancetype)initWithGroupId:(NSData *)groupId
                   groupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
                      groupName:(nullable NSString *)groupName;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@end

NS_ASSUME_NONNULL_END
