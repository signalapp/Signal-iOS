//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSGroupThreadAvatarChangedNotification = @"TSGroupThreadAvatarChangedNotification";
NSString *const TSGroupThread_NotificationKey_UniqueId = @"TSGroupThread_NotificationKey_UniqueId";

@implementation TSGroupThread

#define TSGroupThreadPrefix @"g"

- (instancetype)initWithGroupModel:(TSGroupModel *)groupModel
{
    NSString *uniqueIdentifier = [[self class] threadIdFromGroupId:groupModel.groupId];
    self = [super initWithUniqueId:uniqueIdentifier];

    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

- (instancetype)initWithGroupId:(NSData *)groupId groupType:(GroupType)groupType
{
    NSString *localNumber = [TSAccountManager localNumber];

    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithTitle:nil
                                                         memberIds:@[ localNumber ]
                                                             image:nil
                                                           groupId:groupId
                                                         groupType:groupType
                                                          adminIds:@[ localNumber ]];

    self = [self initWithGroupModel:groupModel];

    if (!self) {
        return self;
    }

    return self;
}

+ (nullable instancetype)threadWithGroupId:(NSData *)groupId transaction:(YapDatabaseReadTransaction *)transaction
{
    return [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId] transaction:transaction];
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
                                   groupType:(GroupType)groupType
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSGroupThread *thread = [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId] transaction:transaction];

    if (!thread) {
        thread = [[self alloc] initWithGroupId:groupId groupType:groupType];
        [thread saveWithTransaction:transaction];
    }

    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId groupType:(GroupType)groupType
{
    __block TSGroupThread *thread;

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupId:groupId groupType:groupType transaction:transaction];
    }];

    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction {
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
    __block TSGroupThread *thread;

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
    }];

    return thread;
}

+ (NSString *)threadIdFromGroupId:(NSData *)groupId
{
    return [TSGroupThreadPrefix stringByAppendingString:[[LKGroupUtilities getDecodedGroupIDAsData:groupId] base64EncodedString]];
}

+ (NSData *)groupIdFromThreadId:(NSString *)threadId
{
    return [NSData dataFromBase64String:[threadId substringWithRange:NSMakeRange(1, threadId.length - 1)]];
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    if (self.isClosedGroup) {
        NSMutableArray<NSString *> *groupMemberIds = [self.groupModel.groupMemberIds mutableCopy];
        if (groupMemberIds == nil) { return @[]; }
        [groupMemberIds removeObject:TSAccountManager.localNumber];
        return [groupMemberIds copy];
    } else {
        return @[ [LKGroupUtilities getDecodedGroupID:self.groupModel.groupId] ];
    }
}

// @returns all threads to which the recipient is a member.
//
// @note If this becomes a hotspot we can extract into a YapDB View.
// As is, the number of groups should be small (dozens, *maybe* hundreds), and we only enumerate them upon SN changes.
+ (NSArray<TSGroupThread *> *)groupThreadsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction
{
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

- (BOOL)isClosedGroup
{
    return (self.groupModel.groupType == closedGroup);
}

- (BOOL)isOpenGroup
{
    return (self.groupModel.groupType == openGroup);
}

- (BOOL)isCurrentUserMemberInGroup
{
    NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
    return [self isUserMemberInGroup:userPublicKey];
}

- (BOOL)isUserMemberInGroup:(NSString *)publicKey
{
    if (publicKey == nil) { return NO; }
    return [self.groupModel.groupMemberIds containsObject:publicKey];
}

- (BOOL)isUserAdminInGroup:(NSString *)publicKey
{
    if (publicKey == nil) { return NO; }
    return [self.groupModel.groupAdminIds containsObject:publicKey];
}

- (NSString *)name
{
    // TODO sometimes groupName is set to the empty string. I'm hesitent to change
    // the semantics here until we have time to thouroughly test the fallout.
    // Instead, see the `groupNameOrDefault` which is appropriate for use when displaying
    // text corresponding to a group.
    return self.groupModel.groupName ?: self.class.defaultGroupName;
}

- (NSString *)nameWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [self name];
}

+ (NSString *)defaultGroupName
{
    return @"Group";
}

- (void)setGroupModel:(TSGroupModel *)newGroupModel withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self.groupModel = newGroupModel;

    [self saveWithTransaction:transaction];

    [transaction addCompletionQueue:dispatch_get_main_queue() completionBlock:^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.groupThreadUpdated object:self.uniqueId];
    }];
}

- (void)setIsOnlyNotifyingForMentions:(BOOL)isOnlyNotifyingForMentions withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self.isOnlyNotifyingForMentions = isOnlyNotifyingForMentions;
    
    [self saveWithTransaction:transaction];
    
    [transaction addCompletionQueue:dispatch_get_main_queue() completionBlock:^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.groupThreadUpdated object:self.uniqueId];
    }];
}

- (void)leaveGroupWithSneakyTransaction
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self leaveGroupWithTransaction:transaction];
    }];
}

- (void)leaveGroupWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSMutableSet<NSString *> *newGroupMemberIDs = [NSMutableSet setWithArray:self.groupModel.groupMemberIds];
    NSString *userPublicKey = TSAccountManager.localNumber;
    if (userPublicKey == nil) { return; }
    [newGroupMemberIDs removeObject:userPublicKey];
    self.groupModel.groupMemberIds = newGroupMemberIDs.allObjects;
    [self saveWithTransaction:transaction];
    [transaction addCompletionQueue:dispatch_get_main_queue() completionBlock:^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.groupThreadUpdated object:self.uniqueId];
    }];
}

#pragma mark - Avatar

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateAvatarWithAttachmentStream:attachmentStream transaction:transaction];
    }];
}

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
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
    NSDictionary *userInfo = @{ TSGroupThread_NotificationKey_UniqueId : self.uniqueId };

    [[NSNotificationCenter defaultCenter] postNotificationName:TSGroupThreadAvatarChangedNotification
                                                        object:self.uniqueId
                                                      userInfo:userInfo];
}

@end

NS_ASSUME_NONNULL_END
