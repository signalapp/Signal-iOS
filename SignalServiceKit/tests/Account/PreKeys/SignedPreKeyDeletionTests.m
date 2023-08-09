//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SDSDatabaseStorage+Objc.h"
#import "SSKBaseTestObjC.h"
#import "SSKSignedPreKeyStore.h"
#import "SignedPrekeyRecord.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface SignedPreKeyDeletionTests : SSKBaseTestObjC

@end

#pragma mark -

@interface SSKSignedPreKeyStore (Tests)

@end

#pragma mark -

@implementation SSKSignedPreKeyStore (Tests)

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId
{
    __block SignedPreKeyRecord *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self loadSignedPreKey:signedPreKeyId transaction:transaction];
    }];
    return result;
}

@end

#pragma mark -

@implementation SignedPreKeyDeletionTests

- (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return [[SSKSignedPreKeyStore alloc] initForIdentity:OWSIdentityACI];
}

- (NSUInteger)signedPreKeyCount
{
    __block NSUInteger result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.signedPreKeyStore loadSignedPreKeysWithTransaction:transaction].count;
    }];
    return result;
}

- (void)testSignedPreKeyDeletion
{
    XCTAssertEqual(0, self.signedPreKeyCount);

    int days = 40;
    int lastPreKeyId = days;

    for (int i = 0; i <= days; i++) { // 41 signed keys are generated, one per day from now until 40 days ago.
        int secondsAgo = (i - days) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[Curve25519 generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record transaction:transaction];
            [self.signedPreKeyStore setCurrentSignedPrekeyId:i transaction:transaction];
        });
    }

    // Sanity check
    XCTAssertEqual(41, self.signedPreKeyCount);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.signedPreKeyStore cullSignedPreKeyRecordsWithTransaction:transaction];
    });

    XCTAssert([self.signedPreKeyStore loadSignedPreKey:lastPreKeyId] != nil);

    // We'll delete every key created 30 or more days ago.
    XCTAssertEqual(30, self.signedPreKeyCount);
}

- (void)testSignedPreKeyDeletionKeepsSomeOldKeys
{
    XCTAssertEqual(0, self.signedPreKeyCount);

    int lastPreKeyId = 10;
    for (int i = 0; i <= 10; i++) {
        // All these keys will be considered "old", since they were created more than 30 days ago.
        int secondsAgo = (i - 40) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[Curve25519 generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        // we only retain accepted keys
        [record markAsAcceptedByService];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record transaction:transaction];
            [self.signedPreKeyStore setCurrentSignedPrekeyId:i transaction:transaction];
        });
    }

    // Sanity check
    XCTAssertEqual(11, self.signedPreKeyCount);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.signedPreKeyStore cullSignedPreKeyRecordsWithTransaction:transaction];
    });

    XCTAssert([self.signedPreKeyStore loadSignedPreKey:lastPreKeyId] != nil);

    // We need to keep 3 "old" keys, plus the "current" key
    XCTAssertEqual(4, self.signedPreKeyCount);
}

- (void)testOlderRecordsNotDeletedIfNoReplacement
{
    XCTAssertEqual(0, self.signedPreKeyCount);

    int days = 3;
    int lastPreKeyId = days;

    for (int i = 0; i <= days; i++) { // 4 signed keys are generated, one per day from now until 3 days ago.
        int secondsAgo = (i - days) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[Curve25519 generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record transaction:transaction];
            [self.signedPreKeyStore setCurrentSignedPrekeyId:i transaction:transaction];
        });
    }

    // Sanity check
    XCTAssertEqual(4, self.signedPreKeyCount);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.signedPreKeyStore cullSignedPreKeyRecordsWithTransaction:transaction];
    });
    XCTAssert([self.signedPreKeyStore loadSignedPreKey:lastPreKeyId] != nil);

    // All records should still be stored.
    XCTAssertEqual(4, self.signedPreKeyCount);
}

@end
