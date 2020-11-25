//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"
#import <YapDatabase/YapDatabase.h>
#import <SessionMessagingKit/OWSIdentityManager.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSContactThreadPrefix = @"c";

@implementation TSContactThread

- (instancetype)initWithContactId:(NSString *)contactId {
    NSString *uniqueIdentifier = [[self class] threadIdFromContactId:contactId];

    self = [super initWithUniqueId:uniqueIdentifier];

    return self;
}

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSContactThread *thread =
        [self fetchObjectWithUniqueID:[self threadIdFromContactId:contactId] transaction:transaction];

    if (!thread) {
        thread = [[TSContactThread alloc] initWithContactId:contactId];
        [thread saveWithTransaction:transaction];
    }

    return thread;
}

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
{
    __block TSContactThread *thread;
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithContactId:contactId transaction:transaction];
    }];

    return thread;
}

+ (nullable instancetype)getThreadWithContactId:(NSString *)contactId transaction:(YapDatabaseReadTransaction *)transaction;
{
    return [TSContactThread fetchObjectWithUniqueID:[self threadIdFromContactId:contactId] transaction:transaction];
}

- (NSString *)contactIdentifier {
    return [[self class] contactIdFromThreadId:self.uniqueId];
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    return @[ self.contactIdentifier ];
}

- (BOOL)isGroupThread {
    return false;
}

- (BOOL)hasSafetyNumbers
{
    return !![[OWSIdentityManager sharedManager] identityKeyForRecipientId:self.contactIdentifier];
}

- (NSString *)name
{
    return [SSKEnvironment.shared.profileManager profileNameForRecipientWithID:self.contactIdentifier avoidingWriteTransaction:YES] ?: self.contactIdentifier;
}

+ (NSString *)threadIdFromContactId:(NSString *)contactId {
    return [TSContactThreadPrefix stringByAppendingString:contactId];
}

+ (NSString *)contactIdFromThreadId:(NSString *)threadId {
    return [threadId substringWithRange:NSMakeRange(1, threadId.length - 1)];
}

@end

NS_ASSUME_NONNULL_END
