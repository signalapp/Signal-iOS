//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalUtilitiesKit/ContactsManagerProtocol.h>
#import <SignalUtilitiesKit/TSYapDatabaseObject.h>
#import <SignalUtilitiesKit/TSAccountManager.h>


NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GroupType) {
    closedGroup = 0, // a.k.a. private group chat
    openGroup = 1, // a.k.a. public group chat
    rssFeed = 2
};

extern const int32_t kGroupIdLength;

@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic) NSArray<NSString *> *groupMemberIds;
@property (nonatomic) NSArray<NSString *> *groupAdminIds;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;
@property (nonatomic) GroupType groupType;
@property (nonatomic) NSMutableSet<NSString *> *removedMembers;

#if TARGET_OS_IOS
@property (nullable, nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(nullable NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId
                    groupType:(GroupType)groupType
                     adminIds:(NSArray<NSString *> *)adminIds;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model contactsManager:(id<ContactsManagerProtocol>)contactsManager;
- (void)updateGroupId: (NSData *)newGroupId;
#endif

@end

NS_ASSUME_NONNULL_END
