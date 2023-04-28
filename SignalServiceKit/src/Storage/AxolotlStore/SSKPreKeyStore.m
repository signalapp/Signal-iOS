//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKPreKeyStore.h"
#import "AxolotlExceptions.h"
#import "PreKeyRecord.h"
#import "SDSKeyValueStore+ObjC.h"
#import "TSStorageKeys.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

#define BATCH_SIZE 100

static const int kPreKeyOfLastResortId = 0xFFFFFF;

NS_ASSUME_NONNULL_BEGIN

NSString *const TSNextPrekeyIdKey = @"TSStorageInternalSettingsNextPreKeyId";

#pragma mark - Private Extension

@interface SDSKeyValueStore (SSKPreKeyStore)

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key transaction:(SDSAnyReadTransaction *)transaction;
- (void)setPreKeyRecord:(PreKeyRecord *)record forKey:(NSString *)key transaction:(SDSAnyWriteTransaction *)transaction;

@end

@implementation SDSKeyValueStore (SSKPreKeyStore)

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.asObjC objectForKey:key ofExpectedType:PreKeyRecord.class transaction:transaction];
}

- (void)setPreKeyRecord:(PreKeyRecord *)record forKey:(NSString *)key transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.asObjC setObject:record ofExpectedType:PreKeyRecord.class forKey:key transaction:transaction];
}

@end

#pragma mark - SSKPreKeyStore

@interface SSKPreKeyStore ()

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;
@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;

@end

#pragma mark - 

@implementation SSKPreKeyStore

- (instancetype)initForIdentity:(OWSIdentity)identity
{
    self = [super init];
    if (!self) {
        return self;
    }

    switch (identity) {
        case OWSIdentityACI:
            _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPreKeyStoreCollection"];
            _metadataStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageInternalSettingsCollection"];
            break;
        case OWSIdentityPNI:
            _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPNIPreKeyStoreCollection"];
            _metadataStore =
                [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPNIPreKeyMetadataCollection"];
            break;
    }

    return self;
}

#pragma mark -

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords
{
    NSMutableArray *preKeyRecords = [NSMutableArray array];

    @synchronized(self) {
        int preKeyId = (int)[self nextPreKeyId];

        OWSLogInfo(@"building %d new preKeys starting from preKeyId: %d", BATCH_SIZE, preKeyId);
        for (int i = 0; i < BATCH_SIZE; i++) {
            ECKeyPair *keyPair = [Curve25519 generateKeyPair];
            PreKeyRecord *record = [[PreKeyRecord alloc] initWithId:preKeyId
                                                            keyPair:keyPair
                                                          createdAt:[NSDate date]];

            [preKeyRecords addObject:record];
            preKeyId++;
        }

        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.metadataStore setInt:preKeyId key:TSNextPrekeyIdKey transaction:transaction];
        });
    }
    return preKeyRecords;
}

- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords transaction:(SDSAnyWriteTransaction *)transaction
{
    for (PreKeyRecord *record in preKeyRecords) {
        [self.keyStore setPreKeyRecord:record forKey:[SDSKeyValueStore keyWithInt:record.Id] transaction:transaction];
    }
}

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
                          transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyStore preKeyRecordForKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
}

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
        transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyStore setPreKeyRecord:record forKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
}

- (void)removePreKey:(int)preKeyId
         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Removing prekeyID: %lu", (unsigned long)preKeyId);

    [self.keyStore removeValueForKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
}

- (NSInteger)nextPreKeyId
{
    __block NSInteger lastPreKeyId;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        lastPreKeyId = [self.metadataStore getInt:TSNextPrekeyIdKey defaultValue:0 transaction:transaction];
    }];

    if (lastPreKeyId < 1) {
        // One-time prekey ids must be > 0 and < kPreKeyOfLastResortId.
        lastPreKeyId = 1 + arc4random_uniform(kPreKeyOfLastResortId - (BATCH_SIZE + 1));
    } else if (lastPreKeyId > kPreKeyOfLastResortId - BATCH_SIZE) {
        // We want to "overflow" to 1 when we reach the "prekey of last resort" id
        // to avoid biasing towards higher values.
        lastPreKeyId = 1;
    }
    OWSAssertDebug(lastPreKeyId > 0 && lastPreKeyId < kPreKeyOfLastResortId);

    return lastPreKeyId;
}

- (void)cullPreKeyRecordsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    NSTimeInterval expirationInterval = kDayInterval * 30;
    NSMutableArray<NSString *> *keys = [[self.keyStore allKeysWithTransaction:transaction] mutableCopy];
    NSMutableSet<NSString *> *keysToRemove = [NSMutableSet new];
    [Batching
        loopObjcWithBatchSize:Batching.kDefaultBatchSize
                    loopBlock:^(BOOL *stop) {
                        NSString *_Nullable key = [keys lastObject];
                        if (key == nil) {
                            *stop = YES;
                            return;
                        }
                        [keys removeLastObject];
                        PreKeyRecord *_Nullable record = [self.keyStore getObjectForKey:key transaction:transaction];
                        if (![record isKindOfClass:[PreKeyRecord class]]) {
                            OWSFailDebug(@"Unexpected value: %@", [record class]);
                            return;
                        }
                        if (record.createdAt == nil) {
                            OWSFailDebug(@"Missing createdAt.");
                            [keysToRemove addObject:key];
                            return;
                        }
                        BOOL shouldRemove = fabs(record.createdAt.timeIntervalSinceNow) > expirationInterval;
                        if (shouldRemove) {
                            OWSLogInfo(
                                @"Removing prekey id: %lu., createdAt: %@", (unsigned long)record.Id, record.createdAt);
                            [keysToRemove addObject:key];
                        }
                    }];
    if (keysToRemove.count < 1) {
        return;
    }
    OWSLogInfo(@"Culling prekeys: %lu", (unsigned long)keysToRemove.count);
    for (NSString *key in keysToRemove) {
        [self.keyStore removeValueForKey:key transaction:transaction];
    }
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
