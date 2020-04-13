//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "TSThread.h"
#import "LKGroupUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;
@class YapDatabaseReadWriteTransaction;

extern NSString *const TSGroupThreadAvatarChangedNotification;
extern NSString *const TSGroupThread_NotificationKey_UniqueId;

@interface TSGroupThread : TSThread

@property (nonatomic, strong) TSGroupModel *groupModel;
@property (nonatomic, readonly) BOOL isRSSFeed;
@property (nonatomic, readonly) BOOL isPublicChat;

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

- (BOOL)isLocalUserInGroup;
- (BOOL)isLocalUserInGroupWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (BOOL)isUserInGroup:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (BOOL)isUserAdminInGroup:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction;

// all group threads containing recipient as a member
+ (NSArray<TSGroupThread *> *)groupThreadsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)updateGroupModel:(TSGroupModel *)newGroupModel withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)leaveGroupWithSneakyTransaction;
- (void)leaveGroupWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)softDeleteGroupThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Avatar

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream;
- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)fireAvatarChangedNotification;

+ (ConversationColorName)defaultConversationColorNameForGroupId:(NSData *)groupId;

@end

NS_ASSUME_NONNULL_END
