//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSGroupThreadAvatarChangedNotification = @"TSGroupThreadAvatarChangedNotification";
NSString *const TSGroupThread_NotificationKey_UniqueId = @"TSGroupThread_NotificationKey_UniqueId";

@implementation TSGroupThread

#define TSGroupThreadPrefix @"g"

// --- CODE GENERATION MARKER

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                    archivalDate:(nullable NSDate *)archivalDate
       archivedAsOfMessageSortId:(nullable NSNumber *)archivedAsOfMessageSortId
           conversationColorName:(ConversationColorName)conversationColorName
                    creationDate:(NSDate *)creationDate
isArchivedByLegacyTimestampForSorting:(BOOL)isArchivedByLegacyTimestampForSorting
                 lastMessageDate:(nullable NSDate *)lastMessageDate
                    messageDraft:(nullable NSString *)messageDraft
                  mutedUntilDate:(nullable NSDate *)mutedUntilDate
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                      groupModel:(TSGroupModel *)groupModel
{
    self = [super initWithUniqueId:uniqueId
                      archivalDate:archivalDate
         archivedAsOfMessageSortId:archivedAsOfMessageSortId
             conversationColorName:conversationColorName
                      creationDate:creationDate
isArchivedByLegacyTimestampForSorting:isArchivedByLegacyTimestampForSorting
                   lastMessageDate:lastMessageDate
                      messageDraft:messageDraft
                    mutedUntilDate:mutedUntilDate
             shouldThreadBeVisible:shouldThreadBeVisible];

    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (instancetype)initWithGroupModel:(TSGroupModel *)groupModel
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
    OWSAssertDebug(groupModel.groupMemberIds.count > 0);
    for (NSString *recipientId in groupModel.groupMemberIds) {
        OWSAssertDebug(recipientId.length > 0);
    }

    NSString *uniqueIdentifier = [[self class] threadIdFromGroupId:groupModel.groupId];
    self = [super initWithUniqueId:uniqueIdentifier];
    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

- (instancetype)initWithGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssertDebug(localNumber.length > 0);

    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithTitle:nil
                                                         memberIds:@[ localNumber ]
                                                             image:nil
                                                           groupId:groupId];

    self = [self initWithGroupModel:groupModel];
    if (!self) {
        return self;
    }

    return self;
}

+ (nullable instancetype)threadWithGroupId:(NSData *)groupId transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    return [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId] transaction:transaction];
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);
    OWSAssertDebug(transaction);

    TSGroupThread *thread = [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId] transaction:transaction];
    if (!thread) {
        thread = [[self alloc] initWithGroupId:groupId];
        [thread saveWithTransaction:transaction];
    }
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    __block TSGroupThread *thread;
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupId:groupId transaction:transaction];
    }];
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
    OWSAssertDebug(transaction);

    TSGroupThread *thread =
        [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupModel.groupId] transaction:transaction];

    if (!thread) {
        thread = [[TSGroupThread alloc] initWithGroupModel:groupModel];
        [thread saveWithTransaction:transaction];
    }
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);

    __block TSGroupThread *thread;
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
    }];
    return thread;
}

+ (NSString *)threadIdFromGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    return [TSGroupThreadPrefix stringByAppendingString:[groupId base64EncodedString]];
}

+ (NSData *)groupIdFromThreadId:(NSString *)threadId
{
    OWSAssertDebug(threadId.length > 0);

    return [NSData dataFromBase64String:[threadId substringWithRange:NSMakeRange(1, threadId.length - 1)]];
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    NSMutableArray<NSString *> *groupMemberIds = [self.groupModel.groupMemberIds mutableCopy];
    if (groupMemberIds == nil) {
        return @[];
    }

    [groupMemberIds removeObject:[TSAccountManager localNumber]];

    return [groupMemberIds copy];
}

// @returns all threads to which the recipient is a member.
//
// @note If this becomes a hotspot we can extract into a YapDB View.
// As is, the number of groups should be small (dozens, *maybe* hundreds), and we only enumerate them upon SN changes.
+ (NSArray<TSGroupThread *> *)groupThreadsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    NSMutableArray<TSGroupThread *> *groupThreads = [NSMutableArray new];

    [self enumerateCollectionObjectsWithTransaction:transaction usingBlock:^(id obj, BOOL *stop) {
        if ([obj isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *groupThread = (TSGroupThread *)obj;
            if ([groupThread.groupModel.groupMemberIds containsObject:recipientId]) {
                [groupThreads addObject:groupThread];
            }
        }
    }];

    return [groupThreads copy];
}

- (BOOL)isGroupThread
{
    return true;
}

- (BOOL)isLocalUserInGroup
{
    NSString *_Nullable localNumber = TSAccountManager.localNumber;
    if (localNumber == nil) {
        return NO;
    }

    return [self.groupModel.groupMemberIds containsObject:localNumber];
}

- (NSString *)name
{
    // TODO sometimes groupName is set to the empty string. I'm hesitent to change
    // the semantics here until we have time to thouroughly test the fallout.
    // Instead, see the `groupNameOrDefault` which is appropriate for use when displaying
    // text corresponding to a group.
    return self.groupModel.groupName ?: self.class.defaultGroupName;
}

+ (NSString *)defaultGroupName
{
    return NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
}

- (void)leaveGroupWithSneakyTransaction
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self leaveGroupWithTransaction:transaction];
    }];
}

- (void)leaveGroupWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSMutableArray<NSString *> *newGroupMemberIds = [self.groupModel.groupMemberIds mutableCopy];
    [newGroupMemberIds removeObject:[TSAccountManager localNumber]];

    self.groupModel.groupMemberIds = newGroupMemberIds;
    [self saveWithTransaction:transaction];
}

- (void)softDeleteGroupThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self removeAllThreadInteractionsWithTransaction:transaction];
    self.shouldThreadBeVisible = NO;
    [self saveWithTransaction:transaction];
}

#pragma mark - Avatar

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateAvatarWithAttachmentStream:attachmentStream transaction:transaction];
    }];
}

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(attachmentStream);
    OWSAssertDebug(transaction);

    self.groupModel.groupImage = [attachmentStream thumbnailImageSmallSync];
    [self saveWithTransaction:transaction];

    [transaction addCompletionQueue:nil
                    completionBlock:^{
                        [self fireAvatarChangedNotification];
                    }];

    // Avatars are stored directly in the database, so there's no need
    // to keep the attachment around after assigning the image.
    [attachmentStream removeWithTransaction:transaction];
}

- (void)fireAvatarChangedNotification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = @{ TSGroupThread_NotificationKey_UniqueId : self.uniqueId };

    [[NSNotificationCenter defaultCenter] postNotificationName:TSGroupThreadAvatarChangedNotification
                                                        object:self.uniqueId
                                                      userInfo:userInfo];
}

+ (ConversationColorName)defaultConversationColorNameForGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    return [self.class stableColorNameForNewConversationWithString:[self threadIdFromGroupId:groupId]];
}

@end

NS_ASSUME_NONNULL_END
