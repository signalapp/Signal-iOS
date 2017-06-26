//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWS104CreateRecipientIdentities.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSRecipientIdentity.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS104CreateRecipientIdentitiesMigrationId = @"104";

/**
 * New SN behavior requires tracking additional state - not just the identity key data.
 * So we wrap the key, along with the new meta-data in an OWSRecipientIdentity.
 */
@implementation OWS104CreateRecipientIdentities

+ (NSString *)migrationId
{
    return OWS104CreateRecipientIdentitiesMigrationId;
}

// Overriding runUp instead of runUpWithTransaction in order to implement a blocking migration.
- (void)runUp
{
    [[OWSRecipientIdentity dbConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        NSMutableDictionary<NSString *, NSData *> *identityKeys = [NSMutableDictionary new];

        [transaction
            enumerateKeysAndObjectsInCollection:TSStorageManagerTrustedKeysCollection
                                     usingBlock:^(
                                         NSString *_Nonnull recipientId, id _Nonnull object, BOOL *_Nonnull stop) {
                                         if (![object isKindOfClass:[NSData class]]) {
                                             DDLogError(
                                                 @"%@ Unexpected object in trusted keys collection key: %@ object: %@",
                                                 self.tag,
                                                 recipientId,
                                                 object);
                                             OWSAssert(NO);
                                             return;
                                         }
                                         NSData *identityKey = (NSData *)object;
                                         [identityKeys setObject:identityKey forKey:recipientId];
                                     }];

        [identityKeys enumerateKeysAndObjectsUsingBlock:^(
            NSString *_Nonnull recipientId, NSData *_Nonnull identityKey, BOOL *_Nonnull stop) {
            DDLogInfo(@"%@ Migrating identity key for recipient: %@", self.tag, recipientId);
            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:NO
                                                     createdAt:[NSDate dateWithTimeIntervalSince1970:0]
                                             verificationState:OWSVerificationStateDefault]
                saveWithTransaction:transaction];
        }];

        [self saveWithTransaction:transaction];
    }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
