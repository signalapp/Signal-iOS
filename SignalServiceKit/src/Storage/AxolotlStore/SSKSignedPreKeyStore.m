//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKSignedPreKeyStore.h"
#import "AxolotlExceptions.h"
#import "SDSKeyValueStore+ObjC.h"
#import "SSKPreKeyStore.h"
#import "SignedPrekeyRecord.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Private Extension

@interface SDSKeyValueStore (SSKSignedPreKeyStore)

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key
                                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)setSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
                       forKey:(NSString *)key
                  transaction:(SDSAnyWriteTransaction *)transaction;

@end

@implementation SDSKeyValueStore (SSKSignedPreKeyStore)

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key
                                              transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.asObjC objectForKey:key ofExpectedType:SignedPreKeyRecord.class transaction:transaction];
}

- (void)setSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
                       forKey:(NSString *)key
                  transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.asObjC setObject:signedPreKeyRecord
            ofExpectedType:SignedPreKeyRecord.class
                    forKey:key
               transaction:transaction];
}

@end

#pragma mark - SSKSignedPreKeyStore

NSString *const kPrekeyCurrentSignedPrekeyIdKey = @"currentSignedPrekeyId";
NSString *const kLastPreKeyRotationDate = @"lastKeyRotationDate";

@interface SSKSignedPreKeyStore ()

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;
@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;

@end

@implementation SSKSignedPreKeyStore {
    OWSIdentity _identity;
}

- (instancetype)initForIdentity:(OWSIdentity)identity
{
    self = [super init];
    if (!self) {
        return self;
    }

    _identity = identity;

    switch (identity) {
        case OWSIdentityACI:
            _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerSignedPreKeyStoreCollection"];
            _metadataStore =
                [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerSignedPreKeyMetadataCollection"];
            break;
        case OWSIdentityPNI:
            _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPNISignedPreKeyStoreCollection"];
            _metadataStore =
                [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPNISignedPreKeyMetadataCollection"];
            break;
    }

    return self;
}

#pragma mark -

- (SignedPreKeyRecord *)generateRandomSignedRecord
{
    ECKeyPair *_Nullable identityKeyPair = [OWSIdentityManagerObjCBridge identityKeyPairForIdentity:_identity];
    OWSAssert(identityKeyPair);

    return [SSKSignedPreKeyStore generateSignedPreKeyWithSignedBy:identityKeyPair];
}

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                       transaction:transaction];
}

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeysWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore allValuesWithTransaction:transaction];
}

- (NSArray<NSString *> *)availableSignedPreKeyIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore allKeysWithTransaction:transaction];
}

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyStore setSignedPreKeyRecord:signedPreKeyRecord
                                  forKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                             transaction:transaction];
}

- (BOOL)containsSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                       transaction:transaction];
}

- (void)removeSignedPreKey:(int)signedPrekeyId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Removing signed prekey id: %lu.", (unsigned long)signedPrekeyId);

    [self.keyStore removeValueForKey:[SDSKeyValueStore keyWithInt:signedPrekeyId] transaction:transaction];
}

- (nullable NSNumber *)currentSignedPrekeyId
{
    __block NSNumber *_Nullable result;
    [self.databaseStorage
        readWithBlock:^(
            SDSAnyReadTransaction *transaction) { result = [self currentSignedPrekeyIdWithTransaction:transaction]; }
                 file:__FILE__
             function:__FUNCTION__
                 line:__LINE__];
    return result;
}

- (nullable NSNumber *)currentSignedPrekeyIdWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.metadataStore getObjectForKey:kPrekeyCurrentSignedPrekeyIdKey transaction:transaction];
}

- (void)setCurrentSignedPrekeyId:(int)value transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"%lu.", (unsigned long)value);
    [self.metadataStore setObject:@(value) key:kPrekeyCurrentSignedPrekeyIdKey transaction:transaction];
}

- (nullable SignedPreKeyRecord *)currentSignedPreKey
{
    __block SignedPreKeyRecord *_Nullable currentRecord;
    [self.databaseStorage
        readWithBlock:^(SDSAnyReadTransaction *transaction) {
            currentRecord = [self currentSignedPreKeyWithTransaction:transaction];
        }
                 file:__FILE__
             function:__FUNCTION__
                 line:__LINE__];

    return currentRecord;
}

- (nullable SignedPreKeyRecord *)currentSignedPreKeyWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSNumber *_Nullable preKeyId = [self.metadataStore getObjectForKey:kPrekeyCurrentSignedPrekeyIdKey
                                                           transaction:transaction];

    if (preKeyId == nil) {
        return nil;
    }

    return [self.keyStore signedPreKeyRecordForKey:preKeyId.stringValue transaction:transaction];
}

- (void)cullSignedPreKeyRecordsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    const NSTimeInterval kSignedPreKeysDeletionTime = 30 * kDayInterval;

    SignedPreKeyRecord *_Nullable currentRecord = [self currentSignedPreKeyWithTransaction:transaction];
    if (!currentRecord) {
        OWSFailDebug(@"Couldn't find current signed pre-key; skipping culling until we have one");
        return;
    }

    NSMutableArray<SignedPreKeyRecord *> *oldSignedPrekeys =
        [[self loadSignedPreKeysWithTransaction:transaction] mutableCopy];
    // Remove the current record from the list.
    for (NSUInteger i = 0; i < oldSignedPrekeys.count; ++i) {
        if (oldSignedPrekeys[i].Id == currentRecord.Id) {
            [oldSignedPrekeys removeObjectAtIndex:i];
            break;
        }
    }

    // Sort the signed prekeys in ascending order of generation time.
    [oldSignedPrekeys sortUsingComparator:^NSComparisonResult(
        SignedPreKeyRecord *left, SignedPreKeyRecord *right) { return [left.generatedAt compare:right.generatedAt]; }];

    unsigned oldSignedPreKeyCount = (unsigned)[oldSignedPrekeys count];

    OWSLogInfo(@"oldSignedPreKeyCount: %u", oldSignedPreKeyCount);

    // Iterate the signed prekeys in ascending order so that we try to delete older keys first.
    for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {
        OWSLogInfo(@"Considering signed prekey id: %d, generatedAt: %@, createdAt: %@, wasAcceptedByService: %d",
            signedPrekey.Id,
            signedPrekey.generatedAt,
            signedPrekey.createdAt,
            signedPrekey.wasAcceptedByService);

        // Always keep at least 3 keys, accepted or otherwise.
        if (oldSignedPreKeyCount <= 3) {
            break;
        }

        // Never delete signed prekeys until they are N days old.
        if (fabs([signedPrekey.generatedAt timeIntervalSinceNow]) < kSignedPreKeysDeletionTime) {
            break;
        }

        // TODO: (PreKey Cleanup)

        oldSignedPreKeyCount--;
        [self removeSignedPreKey:signedPrekey.Id transaction:transaction];
    }
}

#pragma mark - Prekey update failures

- (void)setLastSuccessfulPreKeyRotationDate:(NSDate *)date transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.metadataStore setDate:date key:kLastPreKeyRotationDate transaction:transaction];
}

- (nullable NSDate *)getLastSuccessfulPreKeyRotationDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSDate *lastSuccess = [self.metadataStore getDate:kLastPreKeyRotationDate transaction:transaction];

    // For compatibility with existing signed prekeys, fall back to the last
    if (lastSuccess == nil) {
        SignedPreKeyRecord *currentSignedPreKey = [self currentSignedPreKeyWithTransaction:transaction];
        if (currentSignedPreKey.wasAcceptedByService) {
            // Return the date the last key was signed at as an approximation of last rotation date.
            return currentSignedPreKey.generatedAt;
        }
        return nil;
    }

    return lastSuccess;
}

#pragma mark - Debugging

- (void)logSignedPreKeyReport
{
    NSString *tag = @"SSKSignedPreKeyStore";

    NSNumber *currentId = [self currentSignedPrekeyId];

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        __block int i = 0;

        OWSLogInfo(@"%@ SignedPreKeys Report:", tag);
        OWSLogInfo(@"%@   currentId: %@", tag, currentId);

        NSUInteger count = [self.keyStore numberOfKeysWithTransaction:transaction];
        OWSLogInfo(@"%@   All Keys (count: %lu):", tag, (unsigned long)count);

        [self.keyStore
            enumerateKeysAndObjectsWithTransaction:transaction
                                             block:^(NSString *_Nonnull key,
                                                 id _Nonnull signedPreKeyObject,
                                                 BOOL *_Nonnull stop) {
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

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction
{
    OWSLogWarn(@"");

    [self.keyStore removeAllWithTransaction:transaction];
    [self.metadataStore removeAllWithTransaction:transaction];
}
#endif

@end

NS_ASSUME_NONNULL_END
