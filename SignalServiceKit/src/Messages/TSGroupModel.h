//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

extern const int32_t kGroupIdLength;

@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic) NSArray<NSString *> *groupMemberIds;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;

#if TARGET_OS_IOS
@property (nullable, nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(nullable NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId;

- (instancetype)initWithUniqueId:(nullable NSString *)uniqueId
                         groupId:(NSData *)groupId
                  groupMemberIds:(NSArray<NSString *> *)groupMemberIds
                       groupName:(nullable NSString *)groupName;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@end

NS_ASSUME_NONNULL_END
