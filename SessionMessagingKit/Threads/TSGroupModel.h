//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SessionUtilitiesKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GroupType) {
    closedGroup = 0,
    openGroup = 1,
};

extern const int32_t kGroupIdLength;

@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic) NSArray<NSString *> *groupMemberIds;
@property (nonatomic) NSArray<NSString *> *groupAdminIds;
@property (nullable, readonly, nonatomic) NSString *groupName;
@property (readonly, nonatomic) NSData *groupId;
@property (nonatomic) GroupType groupType;

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
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model;

#endif

@end

NS_ASSUME_NONNULL_END
