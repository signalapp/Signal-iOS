//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableDictionary<NSString *, NSData *> *identityKeys = [NSMutableDictionary new];

    [transaction
        enumerateKeysAndObjectsInCollection:OWSPrimaryStorageTrustedKeysCollection
                                 usingBlock:^(NSString *_Nonnull recipientId, id _Nonnull object, BOOL *_Nonnull stop) {
                                     if (![object isKindOfClass:[NSData class]]) {
                                         OWSFailDebug(
                                             @"Unexpected object in trusted keys collection key: %@ object: %@",
                                             recipientId,
                                             [object class]);
                                         return;
                                     }
                                     NSData *identityKey = (NSData *)object;
                                     [identityKeys setObject:identityKey forKey:recipientId];
                                 }];

    [identityKeys enumerateKeysAndObjectsUsingBlock:^(
        NSString *_Nonnull recipientId, NSData *_Nonnull identityKey, BOOL *_Nonnull stop) {
        OWSLogInfo(@"Migrating identity key for recipient: %@", recipientId);
        [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                               identityKey:identityKey
                                           isFirstKnownKey:NO
                                                 createdAt:[NSDate dateWithTimeIntervalSince1970:0]
                                         verificationState:OWSVerificationStateDefault]
            saveWithTransaction:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END
