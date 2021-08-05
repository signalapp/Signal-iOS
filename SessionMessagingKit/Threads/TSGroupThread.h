//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/TSGroupModel.h>
#import <SessionMessagingKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;
@class YapDatabaseReadWriteTransaction;

extern NSString *const TSGroupThreadAvatarChangedNotification;
extern NSString *const TSGroupThread_NotificationKey_UniqueId;

@interface TSGroupThread : TSThread

@property (nonatomic, strong) TSGroupModel *groupModel;
@property (nonatomic, readonly) BOOL isOpenGroup;
@property (nonatomic, readonly) BOOL isClosedGroup;
@property (nonatomic) BOOL isOnlyNotifyingForMentions;

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel;
+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
                                   groupType:(GroupType) groupType;
+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
                                   groupType:(GroupType) groupType
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (nullable instancetype)threadWithGroupId:(NSData *)groupId transaction:(YapDatabaseReadTransaction *)transaction;

+ (NSString *)threadIdFromGroupId:(NSData *)groupId;

+ (NSString *)defaultGroupName;

- (BOOL)isCurrentUserMemberInGroup;
- (BOOL)isUserMemberInGroup:(NSString *)publicKey;
- (BOOL)isUserAdminInGroup:(NSString *)publicKey;

// all group threads containing recipient as a member
+ (NSArray<TSGroupThread *> *)groupThreadsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)setGroupModel:(TSGroupModel *)newGroupModel withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)setIsOnlyNotifyingForMentions:(BOOL)isOnlyNotifyingForMentions withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)leaveGroupWithSneakyTransaction;
- (void)leaveGroupWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Avatar

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)fireAvatarChangedNotification;

@end

NS_ASSUME_NONNULL_END
