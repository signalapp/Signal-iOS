//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKPreKeyStore.h"
#import "SDSKeyValueStore+ObjC.h"
#import "TSStorageKeys.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionBuilder.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

#define BATCH_SIZE 100

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageInternalSettingsCollection = @"TSStorageInternalSettingsCollection";
NSString *const TSNextPrekeyIdKey = @"TSStorageInternalSettingsNextPreKeyId";

#pragma mark - Private Extension

@interface SDSKeyValueStore (SSKPreKeyStore)

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key transaction:(SDSAnyReadTransaction *)transaction;
- (void)setPreKeyRecord:(PreKeyRecord *)record forKey:(NSString *)key transaction:(SDSAnyWriteTransaction *)transaction;

@end

@implementation SDSKeyValueStore (SSKPreKeyStore)

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key transaction:(SDSAnyReadTransaction *)transaction;
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

@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;
@property (nonatomic, readonly) SDSKeyValueStore *keyStore;

@end

@implementation SSKPreKeyStore

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerPreKeyStoreCollection"];
    _metadataStore = [[SDSKeyValueStore alloc] initWithCollection:TSStorageInternalSettingsCollection];

    return self;
}
#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
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
            PreKeyRecord *record = [[PreKeyRecord alloc] initWithId:preKeyId keyPair:keyPair];

            [preKeyRecords addObject:record];
            preKeyId++;
        }

        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [self.metadataStore setInt:preKeyId key:TSNextPrekeyIdKey transaction:transaction];
        }];
    }
    return preKeyRecords;
}

- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        for (PreKeyRecord *record in preKeyRecords) {
            [self.keyStore setPreKeyRecord:record
                                    forKey:[SDSKeyValueStore keyWithInt:record.Id]
                               transaction:transaction];
        }
    }];
}

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
{
    __block PreKeyRecord *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.keyStore preKeyRecordForKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
    }];
    return result;
}

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyStore setPreKeyRecord:record forKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
    }];
}

- (BOOL)containsPreKey:(int)preKeyId
{
    __block PreKeyRecord *_Nullable preKeyRecord;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        preKeyRecord =
            [self.keyStore preKeyRecordForKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
    }];

    return (preKeyRecord != nil);
}

- (void)removePreKey:(int)preKeyId
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.keyStore removeValueForKey:[SDSKeyValueStore keyWithInt:preKeyId] transaction:transaction];
    }];
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

@end

NS_ASSUME_NONNULL_END
