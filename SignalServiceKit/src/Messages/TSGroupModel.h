//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import "TSYapDatabaseObject.h"

@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic) NSArray<NSString *> *groupMemberIds;
@property (nonatomic) NSString *groupName;
@property (nonatomic) NSData *groupId;

#if TARGET_OS_IOS
@property (nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(NSString *)title
                    memberIds:(NSMutableArray<NSString *> *)memberIds
                        image:(UIImage *)image
                      groupId:(NSData *)groupId;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
#endif

@end
