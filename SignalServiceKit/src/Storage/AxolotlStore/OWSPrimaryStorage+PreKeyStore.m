//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"
#import "TSStorageKeys.h"
#import "YapDatabaseConnection+OWS.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionBuilder.h>
#import <SignalCoreKit/Cryptography.h>

#define OWSPrimaryStoragePreKeyStoreCollection @"TSStorageManagerPreKeyStoreCollection"
#define TSNextPrekeyIdKey @"TSStorageInternalSettingsNextPreKeyId"
#define BATCH_SIZE 100

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPrimaryStorage (PreKeyStore)

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords:(int)batchSize
{
    NSMutableArray *preKeyRecords = [NSMutableArray array];

    @synchronized(self)
    {
        int preKeyId = [self nextPreKeyId:batchSize];

        OWSLogInfo(@"building %d new preKeys starting from preKeyId: %d", batchSize, preKeyId);
        for (int i = 0; i < batchSize; i++) {
            ECKeyPair *keyPair = [Curve25519 generateKeyPair];
            PreKeyRecord *record = [[PreKeyRecord alloc] initWithId:preKeyId keyPair:keyPair];

            [preKeyRecords addObject:record];
            preKeyId++;
        }

        [self.dbReadWriteConnection setInt:preKeyId
                                    forKey:TSNextPrekeyIdKey
                              inCollection:TSStorageInternalSettingsCollection];
    }
    return preKeyRecords;
}

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords
{
    return [self generatePreKeyRecords:BATCH_SIZE];
}

- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords
{
    for (PreKeyRecord *record in preKeyRecords) {
        [self.dbReadWriteConnection setObject:record
                                       forKey:[self keyFromInt:record.Id]
                                 inCollection:OWSPrimaryStoragePreKeyStoreCollection];
    }
}

- (PreKeyRecord *)throws_loadPreKey:(int)preKeyId
{
    PreKeyRecord *preKeyRecord = [self.dbReadConnection preKeyRecordForKey:[self keyFromInt:preKeyId]
                                                              inCollection:OWSPrimaryStoragePreKeyStoreCollection];

    if (!preKeyRecord) {
        OWSRaiseException(InvalidKeyIdException, @"No pre key found matching key id");
    } else {
        return preKeyRecord;
    }
}

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
{
    [self.dbReadWriteConnection setObject:record
                                   forKey:[self keyFromInt:preKeyId]
                             inCollection:OWSPrimaryStoragePreKeyStoreCollection];
}

- (BOOL)containsPreKey:(int)preKeyId
{
    PreKeyRecord *preKeyRecord = [self.dbReadConnection preKeyRecordForKey:[self keyFromInt:preKeyId]
                                                              inCollection:OWSPrimaryStoragePreKeyStoreCollection];
    return (preKeyRecord != nil);
}

- (void)removePreKey:(int)preKeyId
{
    [self.dbReadWriteConnection removeObjectForKey:[self keyFromInt:preKeyId]
                                      inCollection:OWSPrimaryStoragePreKeyStoreCollection];
}

- (int)nextPreKeyId:(int)batchSize
{
    int lastPreKeyId =
        [self.dbReadConnection intForKey:TSNextPrekeyIdKey inCollection:TSStorageInternalSettingsCollection];

    if (lastPreKeyId < 1) {
        // One-time prekey ids must be > 0 and < kPreKeyOfLastResortId.
        lastPreKeyId = 1 + arc4random_uniform(kPreKeyOfLastResortId - (batchSize + 1));
    } else if (lastPreKeyId > kPreKeyOfLastResortId - batchSize) {
        // We want to "overflow" to 1 when we reach the "prekey of last resort" id
        // to avoid biasing towards higher values.
        lastPreKeyId = 1;
    }
    OWSCAssertDebug(lastPreKeyId > 0 && lastPreKeyId < kPreKeyOfLastResortId);

    return lastPreKeyId;
}

@end

NS_ASSUME_NONNULL_END
