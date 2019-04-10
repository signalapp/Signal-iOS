//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;
@class YapDatabaseReadWriteTransaction;

extern NSString *const TSGroupThreadAvatarChangedNotification;
extern NSString *const TSGroupThread_NotificationKey_UniqueId;

@interface TSGroupThread : TSThread

- (instancetype)initWithUniqueId:(nullable NSString *)uniqueId
                    archivalDate:(nullable NSDate *)archivalDate
       archivedAsOfMessageSortId:(nullable NSNumber *)archivedAsOfMessageSortId
           conversationColorName:(NSString *)conversationColorName
                    creationDate:(NSDate *)creationDate
isArchivedByLegacyTimestampForSorting:(BOOL)isArchivedByLegacyTimestampForSorting
                 lastMessageDate:(nullable NSDate *)lastMessageDate
                    messageDraft:(nullable NSString *)messageDraft
                  mutedUntilDate:(nullable NSDate *)mutedUntilDate
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                      groupModel:(TSGroupModel *)groupModel
NS_SWIFT_NAME(init(uniqueId:archivalDate:archivedAsOfMessageSortId:conversationColorName:creationDate:isArchivedByLegacyTimestampForSorting:lastMessageDate:messageDraft:mutedUntilDate:shouldThreadBeVisible:groupModel:));

@property (nonatomic, strong) TSGroupModel *groupModel;

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel;
+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId;
+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (nullable instancetype)threadWithGroupId:(NSData *)groupId transaction:(YapDatabaseReadTransaction *)transaction;

+ (NSString *)threadIdFromGroupId:(NSData *)groupId;

+ (NSString *)defaultGroupName;

- (BOOL)isLocalUserInGroup;

// all group threads containing recipient as a member
+ (NSArray<TSGroupThread *> *)groupThreadsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction;

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
