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
    OWSPrecondition(identityKeyPair);

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

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyStore setSignedPreKeyRecord:signedPreKeyRecord
                                  forKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                             transaction:transaction];
}

- (void)removeSignedPreKey:(int)signedPrekeyId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Removing signed prekey id: %lu.", (unsigned long)signedPrekeyId);

    [self.keyStore removeValueForKey:[SDSKeyValueStore keyWithInt:signedPrekeyId] transaction:transaction];
}

- (void)cullSignedPreKeyRecordsWithJustUploadedSignedPreKey:(SignedPreKeyRecord *)justUploadedSignedPreKey
                                                transaction:(SDSAnyWriteTransaction *)transaction
{
    const NSTimeInterval kSignedPreKeysDeletionTime = 30 * kDayInterval;

    NSMutableArray<SignedPreKeyRecord *> *oldSignedPrekeys =
        [[self loadSignedPreKeysWithTransaction:transaction] mutableCopy];
    // Remove the current record from the list.
    for (NSUInteger i = 0; i < oldSignedPrekeys.count; ++i) {
        if (oldSignedPrekeys[i].Id == justUploadedSignedPreKey.Id) {
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
        OWSLogInfo(@"Considering signed prekey id: %d, generatedAt: %@, createdAt: %@",
            signedPrekey.Id,
            signedPrekey.generatedAt,
            signedPrekey.createdAt);

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

- (void)setLastSuccessfulRotationDate:(NSDate *)date transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.metadataStore setDate:date key:kLastPreKeyRotationDate transaction:transaction];
}

- (nullable NSDate *)getLastSuccessfulRotationDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.metadataStore getDate:kLastPreKeyRotationDate transaction:transaction];
}

#pragma mark - Debugging

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
