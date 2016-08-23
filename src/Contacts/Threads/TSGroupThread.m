//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSGroupThread.h"
#import "NSData+Base64.h"
#import "SignalRecipient.h"
#import <YapDatabase/YapDatabaseTransaction.h>

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

- (instancetype)initWithGroupIdData:(NSData *)groupId
{
    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:groupId];

    self = [self initWithGroupModel:groupModel];
    if (!self) {
        return self;
    }

    return self;
}

+ (instancetype)threadWithGroupModel:(TSGroupModel *)groupModel transaction:(YapDatabaseReadTransaction *)transaction
{
    return [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupModel.groupId] transaction:transaction];
}

+ (instancetype)fetchWithGroupIdData:(NSData *)groupId
{
    return [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId]];
}

+ (instancetype)getOrCreateThreadWithGroupIdData:(NSData *)groupId
{
    TSGroupThread *thread = [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId]];
    if (!thread) {
        thread = [[self alloc] initWithGroupIdData:groupId];
        [thread save];
    }
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

+ (NSString *)threadIdFromGroupId:(NSData *)groupId
{
    return [TSGroupThreadPrefix stringByAppendingString:[groupId base64EncodedString]];
}

+ (NSData *)groupIdFromThreadId:(NSString *)threadId
{
    return [NSData dataFromBase64String:[threadId substringWithRange:NSMakeRange(1, threadId.length - 1)]];
}

- (BOOL)isGroupThread
{
    return true;
}

- (NSString *)name
{
    return self.groupModel.groupName;
}

@end
