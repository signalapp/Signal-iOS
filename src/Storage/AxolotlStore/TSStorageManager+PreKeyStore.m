//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+keyFromIntLong.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionBuilder.h>

#define TSStorageManagerPreKeyStoreCollection @"TSStorageManagerPreKeyStoreCollection"
#define TSNextPrekeyIdKey @"TSStorageInternalSettingsNextPreKeyId"
#define BATCH_SIZE 100

@implementation TSStorageManager (PreKeyStore)

- (PreKeyRecord *)getOrGenerateLastResortKey {
    if ([self containsPreKey:kPreKeyOfLastResortId]) {
        return [self loadPreKey:kPreKeyOfLastResortId];
    } else {
        PreKeyRecord *lastResort =
            [[PreKeyRecord alloc] initWithId:kPreKeyOfLastResortId keyPair:[Curve25519 generateKeyPair]];
        [self storePreKey:kPreKeyOfLastResortId preKeyRecord:lastResort];
        return lastResort;
    }
}

- (NSArray *)generatePreKeyRecords {
    NSMutableArray *preKeyRecords = [NSMutableArray array];

    @synchronized(self) {
        int preKeyId = [self nextPreKeyId];

        DDLogInfo(@"%@ building %d new preKeys starting from preKeyId: %d", self.tag, BATCH_SIZE, preKeyId);
        for (int i = 0; i < BATCH_SIZE; i++) {
            ECKeyPair *keyPair   = [Curve25519 generateKeyPair];
            PreKeyRecord *record = [[PreKeyRecord alloc] initWithId:preKeyId keyPair:keyPair];

            [preKeyRecords addObject:record];
            preKeyId++;
        }

        [self setInt:preKeyId forKey:TSNextPrekeyIdKey inCollection:TSStorageInternalSettingsCollection];
    }
    return preKeyRecords;
}

- (void)storePreKeyRecords:(NSArray *)preKeyRecords {
    for (PreKeyRecord *record in preKeyRecords) {
        [self setObject:record forKey:[self keyFromInt:record.Id] inCollection:TSStorageManagerPreKeyStoreCollection];
    }
}

- (PreKeyRecord *)loadPreKey:(int)preKeyId {
    PreKeyRecord *preKeyRecord =
        [self preKeyRecordForKey:[self keyFromInt:preKeyId] inCollection:TSStorageManagerPreKeyStoreCollection];

    if (!preKeyRecord) {
        @throw [NSException exceptionWithName:InvalidKeyIdException
                                       reason:@"No pre key found matching key id"
                                     userInfo:@{}];
    } else {
        return preKeyRecord;
    }
}

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record {
    [self setObject:record forKey:[self keyFromInt:preKeyId] inCollection:TSStorageManagerPreKeyStoreCollection];
}

- (BOOL)containsPreKey:(int)preKeyId {
    PreKeyRecord *preKeyRecord =
        [self preKeyRecordForKey:[self keyFromInt:preKeyId] inCollection:TSStorageManagerPreKeyStoreCollection];
    return (preKeyRecord != nil);
}

- (void)removePreKey:(int)preKeyId {
    [self removeObjectForKey:[self keyFromInt:preKeyId] inCollection:TSStorageManagerPreKeyStoreCollection];
}

- (int)nextPreKeyId {
    int lastPreKeyId = [self intForKey:TSNextPrekeyIdKey inCollection:TSStorageInternalSettingsCollection];

    if (lastPreKeyId < 1) {
        // One-time prekey ids must be > 0 and < kPreKeyOfLastResortId.
        lastPreKeyId = 1 + arc4random_uniform(kPreKeyOfLastResortId - (BATCH_SIZE + 1));
    } else if (lastPreKeyId > kPreKeyOfLastResortId - BATCH_SIZE) {
        // We want to "overflow" to 1 when we reach the "prekey of last resort" id
        // to avoid biasing towards higher values.
        lastPreKeyId = 1;
    }
    OWSCAssert(lastPreKeyId > 0 && lastPreKeyId < kPreKeyOfLastResortId);

    return lastPreKeyId;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@+PreKeyStore]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
