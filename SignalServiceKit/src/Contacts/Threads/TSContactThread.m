//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"
#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "NotificationsProtocol.h"
#import "OWSIdentityManager.h"
#import "TextSecureKitEnv.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

#define TSContactThreadPrefix @"c"

@implementation TSContactThread

- (instancetype)initWithContactId:(NSString *)contactId {
    NSString *uniqueIdentifier = [[self class] threadIdFromContactId:contactId];

    OWSAssert(contactId.length > 0);

    self = [super initWithUniqueId:uniqueIdentifier];

    return self;
}

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
                                         relay:(nullable NSString *)relay
{
    OWSAssert(contactId.length > 0);

    SignalRecipient *recipient =
        [SignalRecipient recipientWithTextSecureIdentifier:contactId withTransaction:transaction];

    if (!recipient) {
        // If no recipient record exists for that contactId, create an empty record
        // for immediate use, then ask ContactsUpdater to try to update it async.
        recipient =
            [[SignalRecipient alloc] initWithTextSecureIdentifier:contactId
                                                            relay:relay];
        [recipient saveWithTransaction:transaction];

        // Update recipient with Server record async.
        [[ContactsUpdater sharedUpdater] lookupIdentifier:contactId
            success:^(SignalRecipient *recipient) {
            }
            failure:^(NSError *error) {
                DDLogWarn(@"Failed to lookup contact with error:%@", error);
            }];
    }

    return [self getOrCreateThreadWithContactId:contactId transaction:transaction];
}

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssert(contactId.length > 0);

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
    OWSAssert(contactId.length > 0);

    __block TSContactThread *thread;
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
    return @[self.contactIdentifier];
}

- (BOOL)isGroupThread {
    return false;
}

- (BOOL)hasSafetyNumbers
{
    return !![[OWSIdentityManager sharedManager] identityKeyForRecipientId:self.contactIdentifier];
}

// TODO deprecate this? seems weird to access the displayName in the DB model
- (NSString *)name
{
    return [[TextSecureKitEnv sharedEnv].contactsManager displayNameForPhoneIdentifier:self.contactIdentifier];
}


+ (NSString *)threadIdFromContactId:(NSString *)contactId {
    return [TSContactThreadPrefix stringByAppendingString:contactId];
}

+ (NSString *)contactIdFromThreadId:(NSString *)threadId {
    return [threadId substringWithRange:NSMakeRange(1, threadId.length - 1)];
}

@end

NS_ASSUME_NONNULL_END
