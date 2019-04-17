//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"
#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "NotificationsProtocol.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSContactThreadPrefix = @"c";

@implementation TSContactThread

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
              hasDismissedOffers:(BOOL)hasDismissedOffers
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

    _hasDismissedOffers = hasDismissedOffers;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (instancetype)initWithContactId:(NSString *)contactId {
    NSString *uniqueIdentifier = [[self class] threadIdFromContactId:contactId];

    OWSAssertDebug(contactId.length > 0);

    self = [super initWithUniqueId:uniqueIdentifier];

    return self;
}

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssertDebug(contactId.length > 0);

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
    OWSAssertDebug(contactId.length > 0);

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
    return [SSKEnvironment.shared.contactsManager displayNameForPhoneIdentifier:self.contactIdentifier];
}

+ (NSString *)threadIdFromContactId:(NSString *)contactId {
    return [TSContactThreadPrefix stringByAppendingString:contactId];
}

+ (NSString *)contactIdFromThreadId:(NSString *)threadId {
    return [threadId substringWithRange:NSMakeRange(1, threadId.length - 1)];
}

+ (NSString *)conversationColorNameForRecipientId:(NSString *)recipientId
                                      transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);

    TSContactThread *_Nullable contactThread =
        [TSContactThread getThreadWithContactId:recipientId transaction:transaction];
    if (contactThread) {
        return contactThread.conversationColorName;
    }
    return [self stableColorNameForNewConversationWithString:recipientId];
}

@end

NS_ASSUME_NONNULL_END
