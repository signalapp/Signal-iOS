//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"
#import "YapDatabaseConnection+OWS.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <Curve25519Kit/Ed25519.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageSignedPreKeyStoreCollection = @"TSStorageManagerSignedPreKeyStoreCollection";
NSString *const OWSPrimaryStorageSignedPreKeyMetadataCollection = @"TSStorageManagerSignedPreKeyMetadataCollection";
NSString *const OWSPrimaryStorageKeyPrekeyUpdateFailureCount = @"prekeyUpdateFailureCount";
NSString *const OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate = @"firstPrekeyUpdateFailureDate";
NSString *const OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId = @"currentSignedPrekeyId";

@implementation OWSPrimaryStorage (SignedPreKeyStore)

- (SignedPreKeyRecord *)generateRandomSignedRecord
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    // Signed prekey ids must be > 0.
    int preKeyId = 1 + arc4random_uniform(INT32_MAX - 1);
    ECKeyPair *_Nullable identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];
    return [[SignedPreKeyRecord alloc]
         initWithId:preKeyId
            keyPair:keyPair
          signature:[Ed25519 sign:keyPair.publicKey.prependKeyType withKeyPair:identityKeyPair]
        generatedAt:[NSDate date]];
}

- (SignedPreKeyRecord *)loadSignedPrekey:(int)signedPreKeyId
{
    SignedPreKeyRecord *preKeyRecord =
        [self.dbReadConnection signedPreKeyRecordForKey:[self keyFromInt:signedPreKeyId]
                                           inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];

    if (!preKeyRecord) {
        OWSRaiseException(InvalidKeyIdException, @"No signed pre key found matching key id");
    } else {
        return preKeyRecord;
    }
}

- (nullable SignedPreKeyRecord *)loadSignedPrekeyOrNil:(int)signedPreKeyId
{
    return [self.dbReadConnection signedPreKeyRecordForKey:[self keyFromInt:signedPreKeyId]
                                              inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
}

- (NSArray *)loadSignedPreKeys
{
    NSMutableArray *signedPreKeyRecords = [NSMutableArray array];

    YapDatabaseConnection *conn = [self newDatabaseConnection];

    [conn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [transaction enumerateRowsInCollection:OWSPrimaryStorageSignedPreKeyStoreCollection
                                    usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
                                        [signedPreKeyRecords addObject:object];
                                    }];
    }];

    return signedPreKeyRecords;
}

- (void)storeSignedPreKey:(int)signedPreKeyId signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
{
    [self.dbReadWriteConnection setObject:signedPreKeyRecord
                                   forKey:[self keyFromInt:signedPreKeyId]
                             inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
}

- (BOOL)containsSignedPreKey:(int)signedPreKeyId
{
    PreKeyRecord *preKeyRecord =
        [self.dbReadConnection signedPreKeyRecordForKey:[self keyFromInt:signedPreKeyId]
                                           inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
    return (preKeyRecord != nil);
}

- (void)removeSignedPreKey:(int)signedPrekeyId
{
    [self.dbReadWriteConnection removeObjectForKey:[self keyFromInt:signedPrekeyId]
                                      inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
}

- (nullable NSNumber *)currentSignedPrekeyId
{
    return [self.dbReadConnection objectForKey:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId
                                  inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (void)setCurrentSignedPrekeyId:(int)value
{
    [self.dbReadWriteConnection setObject:@(value)
                                   forKey:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId
                             inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (nullable SignedPreKeyRecord *)currentSignedPreKey
{
    __block SignedPreKeyRecord *_Nullable currentRecord;

    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        NSNumber *_Nullable preKeyId = [transaction objectForKey:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId
                                                    inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];

        if (preKeyId == nil) {
            return;
        }

        currentRecord =
            [transaction objectForKey:preKeyId.stringValue inCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
    }];

    return currentRecord;
}

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount
{
    NSNumber *_Nullable value = [self.dbReadConnection objectForKey:OWSPrimaryStorageKeyPrekeyUpdateFailureCount
                                                       inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
    // Will default to zero.
    return [value intValue];
}

- (void)clearPrekeyUpdateFailureCount
{
    [self.dbReadWriteConnection removeObjectForKey:OWSPrimaryStorageKeyPrekeyUpdateFailureCount
                                      inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (int)incrementPrekeyUpdateFailureCount
{
    return [self.dbReadWriteConnection incrementIntForKey:OWSPrimaryStorageKeyPrekeyUpdateFailureCount
                                             inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (nullable NSDate *)firstPrekeyUpdateFailureDate
{
    return [self.dbReadConnection dateForKey:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate
                                inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value
{
    [self.dbReadWriteConnection setDate:value
                                 forKey:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate
                           inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

- (void)clearFirstPrekeyUpdateFailureDate
{
    [self.dbReadWriteConnection removeObjectForKey:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate
                                      inCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];
}

#pragma mark - Debugging

- (void)logSignedPreKeyReport
{
    NSString *tag = @"[OWSPrimaryStorage (SignedPreKeyStore)]";

    NSNumber *currentId = [self currentSignedPrekeyId];
    NSDate *firstPrekeyUpdateFailureDate = [self firstPrekeyUpdateFailureDate];
    NSUInteger prekeyUpdateFailureCount = [self prekeyUpdateFailureCount];

    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        __block int i = 0;

        OWSLogInfo(@"%@ SignedPreKeys Report:", tag);
        OWSLogInfo(@"%@   currentId: %@", tag, currentId);
        OWSLogInfo(@"%@   firstPrekeyUpdateFailureDate: %@", tag, firstPrekeyUpdateFailureDate);
        OWSLogInfo(@"%@   prekeyUpdateFailureCount: %lu", tag, (unsigned long)prekeyUpdateFailureCount);

        NSUInteger count = [transaction numberOfKeysInCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
        OWSLogInfo(@"%@   All Keys (count: %lu):", tag, (unsigned long)count);

        [transaction
            enumerateKeysAndObjectsInCollection:OWSPrimaryStorageSignedPreKeyStoreCollection
                                     usingBlock:^(
                                         NSString *_Nonnull key, id _Nonnull signedPreKeyObject, BOOL *_Nonnull stop) {
                                         i++;
                                         if (![signedPreKeyObject isKindOfClass:[SignedPreKeyRecord class]]) {
                                             OWSFailDebug(@"%@ Was expecting SignedPreKeyRecord, but found: %@",
                                                 tag,
                                                 [signedPreKeyObject class]);
                                             return;
                                         }
                                         SignedPreKeyRecord *signedPreKeyRecord
                                             = (SignedPreKeyRecord *)signedPreKeyObject;
                                         OWSLogInfo(@"%@     #%d <SignedPreKeyRecord: id: %d, generatedAt: %@, "
                                                    @"wasAcceptedByService:%@, signature: %@",
                                             tag,
                                             i,
                                             signedPreKeyRecord.Id,
                                             signedPreKeyRecord.generatedAt,
                                             (signedPreKeyRecord.wasAcceptedByService ? @"YES" : @"NO"),
                                             signedPreKeyRecord.signature);
                                     }];
    }];
}

@end

NS_ASSUME_NONNULL_END
