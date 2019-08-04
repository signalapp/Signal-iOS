//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKSignedPreKeyStore.h"
#import "OWSIdentityManager.h"
#import "SDSKeyValueStore+ObjC.h"
#import "SSKPreKeyStore.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <Curve25519Kit/Ed25519.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

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
                                              transaction:(SDSAnyReadTransaction *)transaction;
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
    NSInteger value = [self getInt:key transaction:transaction];
    value++;
    [self setInt:value key:key transaction:transaction];
    return value;
}

@end

#pragma mark - SSKSignedPreKeyStore

NSString *const OWSPrimaryStorageSignedPreKeyStoreCollection = @"TSStorageManagerSignedPreKeyStoreCollection";
NSString *const OWSPrimaryStorageSignedPreKeyMetadataCollection = @"TSStorageManagerSignedPreKeyMetadataCollection";
NSString *const OWSPrimaryStorageKeyPrekeyUpdateFailureCount = @"prekeyUpdateFailureCount";
NSString *const OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate = @"firstPrekeyUpdateFailureDate";
NSString *const OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId = @"currentSignedPrekeyId";

@interface SSKSignedPreKeyStore ()

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;
@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;

@end

@implementation SSKSignedPreKeyStore

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyStore = [[SDSKeyValueStore alloc] initWithCollection:OWSPrimaryStorageSignedPreKeyStoreCollection];
    _metadataStore = [[SDSKeyValueStore alloc] initWithCollection:OWSPrimaryStorageSignedPreKeyMetadataCollection];

    return self;
}

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (SignedPreKeyRecord *)generateRandomSignedRecord
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    // Signed prekey ids must be > 0.
    int preKeyId = 1 + arc4random_uniform(INT32_MAX - 1);
    ECKeyPair *_Nullable identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];
    OWSAssert(identityKeyPair);

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

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId
{
    __block SignedPreKeyRecord *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                             transaction:transaction];
    }];
    return result;
}

- (NSArray *)loadSignedPreKeys
{
    __block NSArray *signedPreKeyRecords;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        signedPreKeyRecords = [self.keyStore allValuesWithTransaction:transaction];
    }];
    return signedPreKeyRecords;
}

- (void)storeSignedPreKey:(int)signedPreKeyId signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyStore setSignedPreKeyRecord:signedPreKeyRecord
                                      forKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                 transaction:transaction];
    }];
}

- (BOOL)containsSignedPreKey:(int)signedPreKeyId
{
    __block SignedPreKeyRecord *signedPreKeyRecord;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        signedPreKeyRecord = [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                                         transaction:transaction];
    }];
    return (signedPreKeyRecord != nil);
}

- (void)removeSignedPreKey:(int)signedPrekeyId
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyStore removeValueForKey:[SDSKeyValueStore keyWithInt:signedPrekeyId] transaction:transaction];
    }];
}

- (nullable NSNumber *)currentSignedPrekeyId
{
    __block NSNumber *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.metadataStore getObject:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId transaction:transaction];
    }];
    return result;
}

- (void)setCurrentSignedPrekeyId:(int)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore setObject:@(value)
                                  key:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId
                          transaction:transaction];
    }];
}

- (nullable SignedPreKeyRecord *)currentSignedPreKey
{
    __block SignedPreKeyRecord *_Nullable currentRecord;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSNumber *_Nullable preKeyId =
            [self.metadataStore getObject:OWSPrimaryStorageKeyPrekeyCurrentSignedPrekeyId transaction:transaction];

        if (preKeyId == nil) {
            return;
        }

        currentRecord = [self.keyStore signedPreKeyRecordForKey:preKeyId.stringValue transaction:transaction];
    }];

    return currentRecord;
}

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount
{
    __block NSNumber *_Nullable value;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        value = [self.metadataStore getObject:OWSPrimaryStorageKeyPrekeyUpdateFailureCount transaction:transaction];
    }];
    // Will default to zero.
    return [value intValue];
}

- (void)clearPrekeyUpdateFailureCount
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore removeValueForKey:OWSPrimaryStorageKeyPrekeyUpdateFailureCount transaction:transaction];
    }];
}

- (NSInteger)incrementPrekeyUpdateFailureCount
{
    __block NSInteger result;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        result = [self.metadataStore incrementIntForKey:OWSPrimaryStorageKeyPrekeyUpdateFailureCount
                                            transaction:transaction];
    }];
    return result;
}

- (nullable NSDate *)firstPrekeyUpdateFailureDate
{
    __block NSDate *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.metadataStore getDate:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate transaction:transaction];
    }];
    return result;
}

- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore setDate:value key:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate transaction:transaction];
    }];
}

- (void)clearFirstPrekeyUpdateFailureDate
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore removeValueForKey:OWSPrimaryStorageKeyFirstPrekeyUpdateFailureDate transaction:transaction];
    }];
}

#pragma mark - Debugging

- (void)logSignedPreKeyReport
{
    NSString *tag = @"[OWSPrimaryStorage (SignedPreKeyStore)]";

    NSNumber *currentId = [self currentSignedPrekeyId];
    NSDate *firstPrekeyUpdateFailureDate = [self firstPrekeyUpdateFailureDate];
    NSUInteger prekeyUpdateFailureCount = [self prekeyUpdateFailureCount];

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        __block int i = 0;

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

@end

NS_ASSUME_NONNULL_END
