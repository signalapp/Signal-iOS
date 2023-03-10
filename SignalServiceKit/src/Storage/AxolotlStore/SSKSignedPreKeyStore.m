//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKSignedPreKeyStore.h"
#import "AxolotlExceptions.h"
#import "NSData+keyVersionByte.h"
#import "OWSIdentityManager.h"
#import "SDSKeyValueStore+ObjC.h"
#import "SSKPreKeyStore.h"
#import "SignedPrekeyRecord.h"
#import <Curve25519Kit/Ed25519.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Private Extension

@interface SDSKeyValueStore (SSKSignedPreKeyStore)

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key
                                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)setSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
                       forKey:(NSString *)key
                  transaction:(SDSAnyWriteTransaction *)transaction;

- (NSInteger)incrementIntForKey:(NSString *)key transaction:(SDSAnyWriteTransaction *)transaction;

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

- (NSInteger)incrementIntForKey:(NSString *)key transaction:(SDSAnyWriteTransaction *)transaction
{
    NSInteger value = [self getInt:key defaultValue:0 transaction:transaction];
    value++;
    [self setInt:value key:key transaction:transaction];
    return value;
}

@end

#pragma mark - SSKSignedPreKeyStore

NSString *const kPrekeyUpdateFailureCountKey = @"prekeyUpdateFailureCount";
NSString *const kFirstPrekeyUpdateFailureDateKey = @"firstPrekeyUpdateFailureDate";
NSString *const kPrekeyCurrentSignedPrekeyIdKey = @"currentSignedPrekeyId";

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

+ (SignedPreKeyRecord *)generateSignedPreKeySignedWithIdentityKey:(ECKeyPair *)identityKeyPair
{
    OWSAssert(identityKeyPair);

    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    // Signed prekey ids must be > 0.
    int preKeyId = 1 + (int)arc4random_uniform(INT32_MAX - 1);

    @try {
        NSData *signature = [Ed25519 throws_sign:keyPair.publicKey.prependKeyType withKeyPair:identityKeyPair];
        return [[SignedPreKeyRecord alloc] initWithId:preKeyId
                                              keyPair:keyPair
                                            signature:signature
                                          generatedAt:[NSDate date]];
    } @catch (NSException *exception) {
        // throws_sign only throws when the data to sign is empty or `keyPair` is nil.
        // Neither of which should happen.
        OWSFail(@"exception: %@", exception);
        return nil;
    }
}

- (SignedPreKeyRecord *)generateRandomSignedRecord
{
    ECKeyPair *_Nullable identityKeyPair = [[OWSIdentityManager shared] identityKeyPairForIdentity:_identity];
    OWSAssert(identityKeyPair);

    return [SSKSignedPreKeyStore generateSignedPreKeySignedWithIdentityKey:identityKeyPair];
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
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.metadataStore getObjectForKey:kPrekeyCurrentSignedPrekeyIdKey transaction:transaction];
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];
    return result;
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
    unsigned oldAcceptedSignedPreKeyCount = 0;
    for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {
        if (signedPrekey.wasAcceptedByService) {
            oldAcceptedSignedPreKeyCount++;
        }
    }

    OWSLogInfo(@"oldSignedPreKeyCount: %u, oldAcceptedSignedPreKeyCount: %u",
        oldSignedPreKeyCount,
        oldAcceptedSignedPreKeyCount);

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

        // We try to keep a minimum of 3 "old, accepted" signed prekeys.
        if (signedPrekey.wasAcceptedByService) {
            if (oldAcceptedSignedPreKeyCount <= 3) {
                continue;
            } else {
                oldAcceptedSignedPreKeyCount--;
            }
        }

        if (signedPrekey.wasAcceptedByService) {
            OWSProdInfo([OWSAnalyticsEvents prekeysDeletedOldAcceptedSignedPrekey]);
        } else {
            OWSProdInfo([OWSAnalyticsEvents prekeysDeletedOldUnacceptedSignedPrekey]);
        }

        oldSignedPreKeyCount--;
        [self removeSignedPreKey:signedPrekey.Id transaction:transaction];
    }
}

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCountWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSNumber *_Nullable value = [self.metadataStore getObjectForKey:kPrekeyUpdateFailureCountKey
                                                        transaction:transaction];
    // Will default to zero.
    return [value intValue];
}

- (void)clearPrekeyUpdateFailureCountWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [self.metadataStore removeValueForKey:kPrekeyUpdateFailureCountKey transaction:transaction];
    [self.metadataStore removeValueForKey:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
}

- (NSInteger)incrementPrekeyUpdateFailureCountWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    NSInteger failureCount = [self.metadataStore incrementIntForKey:kPrekeyUpdateFailureCountKey
                                                        transaction:transaction];

    OWSLogInfo(@"new failureCount: %ld", (long)failureCount);

    if (failureCount == 1 || ![self firstPrekeyUpdateFailureDateWithTransaction:transaction]) {
        // If this is the "first" failure, record the timestamp of that failure.
        [self.metadataStore setDate:[NSDate new] key:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
    }

    return failureCount;
}

- (void)setPrekeyUpdateFailureCount:(NSInteger)count
                   firstFailureDate:(NSDate *)firstFailureDate
                        transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.metadataStore setInt:count key:kPrekeyUpdateFailureCountKey transaction:transaction];
    [self.metadataStore setDate:firstFailureDate key:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
}

- (nullable NSDate *)firstPrekeyUpdateFailureDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.metadataStore getDate:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
}


#pragma mark - Debugging

- (void)logSignedPreKeyReport
{
    NSString *tag = @"SSKSignedPreKeyStore";

    NSNumber *currentId = [self currentSignedPrekeyId];

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        __block int i = 0;

        NSDate *firstPrekeyUpdateFailureDate = [self firstPrekeyUpdateFailureDateWithTransaction:transaction];
        NSInteger prekeyUpdateFailureCount = [self prekeyUpdateFailureCountWithTransaction:transaction];

        OWSLogInfo(@"%@ SignedPreKeys Report:", tag);
        OWSLogInfo(@"%@   currentId: %@", tag, currentId);
        OWSLogInfo(@"%@   firstPrekeyUpdateFailureDate: %@", tag, firstPrekeyUpdateFailureDate);
        OWSLogInfo(@"%@   prekeyUpdateFailureCount: %lu", tag, (unsigned long)prekeyUpdateFailureCount);

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
