//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"
#import <YapDatabase/YapDatabase.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSContactThreadPrefix = @"c";

@implementation TSContactThread

- (instancetype)initWithContactSessionID:(NSString *)contactSessionID {
    NSString *uniqueIdentifier = [[self class] threadIDFromContactSessionID:contactSessionID];

    self = [super initWithUniqueId:uniqueIdentifier];

    return self;
}

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSContactThread *thread =
        [self fetchObjectWithUniqueID:[self threadIDFromContactSessionID:contactSessionID] transaction:transaction];

    if (!thread) {
        thread = [[TSContactThread alloc] initWithContactSessionID:contactSessionID];
        [thread saveWithTransaction:transaction];
    }

    return thread;
}

+ (instancetype)getOrCreateThreadWithContactSessionID:(NSString *)contactSessionID
{
    __block TSContactThread *thread;
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithContactSessionID:contactSessionID transaction:transaction];
    }];

    return thread;
}

+ (nullable instancetype)getThreadWithContactSessionID:(NSString *)contactSessionID transaction:(YapDatabaseReadTransaction *)transaction;
{
    return [TSContactThread fetchObjectWithUniqueID:[self threadIDFromContactSessionID:contactSessionID] transaction:transaction];
}

- (NSString *)contactSessionID {
    return [[self class] contactSessionIDFromThreadID:self.uniqueId];
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    return @[ self.contactSessionID ];
}

- (BOOL)isGroupThread
{
    return NO;
}

- (NSString *)name
{
    NSString *sessionID = self.contactSessionID;
    SNContact *contact = [LKStorage.shared getContactWithSessionID:sessionID];
    return [contact displayNameFor:SNContactContextRegular] ?: sessionID;
}

- (NSString *)nameWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *sessionID = self.contactSessionID;
    SNContact *contact = [LKStorage.shared getContactWithSessionID:sessionID using:transaction];
    return [contact displayNameFor:SNContactContextRegular] ?: sessionID;
}

+ (NSString *)threadIDFromContactSessionID:(NSString *)contactSessionID {
    return [TSContactThreadPrefix stringByAppendingString:contactSessionID];
}

+ (NSString *)contactSessionIDFromThreadID:(NSString *)threadId {
    return [threadId substringWithRange:NSMakeRange(1, threadId.length - 1)];
}

@end

NS_ASSUME_NONNULL_END
