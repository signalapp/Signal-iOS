//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKSignedPreKeyStore.h"
#import "OWSIdentityManager.h"
#import "SDSKeyValueStore+ObjC.h"
#import "SSKPreKeyStore.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
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

@implementation SSKSignedPreKeyStore

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerSignedPreKeyStoreCollection"];
    _metadataStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerSignedPreKeyMetadataCollection"];

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
    ECKeyPair *_Nullable identityKeyPair = [[OWSIdentityManager shared] identityKeyPair];
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
                                  protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self loadSignedPreKey:signedPreKeyId transaction:transaction];
}

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                       transaction:transaction];
}

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeysWithProtocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;
    
    return [self loadSignedPreKeysWithTransaction:transaction];
}

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeysWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore allValuesWithTransaction:transaction];
}

- (NSArray<NSString *> *)availableSignedPreKeyIdsWithProtocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;
    
    return [self availableSignedPreKeyIdsWithTransaction:transaction];
}

- (NSArray<NSString *> *)availableSignedPreKeyIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore allKeysWithTransaction:transaction];
}

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
          protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    [self storeSignedPreKey:signedPreKeyId signedPreKeyRecord:signedPreKeyRecord transaction:transaction];
}

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyStore setSignedPreKeyRecord:signedPreKeyRecord
                                  forKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                             transaction:transaction];
}

- (BOOL)containsSignedPreKey:(int)signedPreKeyId protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self containsSignedPreKey:signedPreKeyId transaction:transaction];
}

- (BOOL)containsSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore signedPreKeyRecordForKey:[SDSKeyValueStore keyWithInt:signedPreKeyId]
                                       transaction:transaction];
}

- (void)removeSignedPreKey:(int)signedPrekeyId protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    [self removeSignedPreKey:signedPrekeyId transaction:transaction];
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
    }];
    return result;
}

- (void)setCurrentSignedPrekeyId:(int)value
{
    OWSLogInfo(@"%lu.", (unsigned long)value);
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore setObject:@(value) key:kPrekeyCurrentSignedPrekeyIdKey transaction:transaction];
    });
}

- (nullable SignedPreKeyRecord *)currentSignedPreKey
{
    __block SignedPreKeyRecord *_Nullable currentRecord;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSNumber *_Nullable preKeyId = [self.metadataStore getObjectForKey:kPrekeyCurrentSignedPrekeyIdKey
                                                               transaction:transaction];

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
        value = [self.metadataStore getObjectForKey:kPrekeyUpdateFailureCountKey transaction:transaction];
    }];
    // Will default to zero.
    return [value intValue];
}

- (void)clearPrekeyUpdateFailureCount
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore removeValueForKey:kPrekeyUpdateFailureCountKey transaction:transaction];
    });
}

- (NSInteger)incrementPrekeyUpdateFailureCount
{
    __block NSInteger result;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        result = [self.metadataStore incrementIntForKey:kPrekeyUpdateFailureCountKey transaction:transaction];
    });
    return result;
}

- (nullable NSDate *)firstPrekeyUpdateFailureDate
{
    __block NSDate *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.metadataStore getDate:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
    }];
    return result;
}

- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore setDate:value key:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
    });
}

- (void)clearFirstPrekeyUpdateFailureDate
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.metadataStore removeValueForKey:kFirstPrekeyUpdateFailureDateKey transaction:transaction];
    });
}

#pragma mark - Debugging

- (void)logSignedPreKeyReport
{
    NSString *tag = @"SSKSignedPreKeyStore";

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
