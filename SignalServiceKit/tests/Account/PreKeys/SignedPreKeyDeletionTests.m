//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SDSDatabaseStorage+Objc.h"
#import "SSKBaseTestObjC.h"
#import "SSKSignedPreKeyStore.h"
#import "SignedPrekeyRecord.h"
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

- (void)testSignedPreKeyDeletion
{
    int days = 40;

    SignedPreKeyRecord *justUploadedSignedPreKeyRecord;
    for (int i = 0; i <= days; i += 5) { // 5 keys are generated: [0, 10, ..., 40]
        int secondsAgo = (i - days) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[ECKeyPair generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record transaction:transaction];
        });
        justUploadedSignedPreKeyRecord = record;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.signedPreKeyStore cullSignedPreKeyRecordsWithJustUploadedSignedPreKey:justUploadedSignedPreKeyRecord
                                                                        transaction:transaction];
    });

    XCTAssertNil([self.signedPreKeyStore loadSignedPreKey:0]);
    XCTAssertNil([self.signedPreKeyStore loadSignedPreKey:5]);
    XCTAssertNil([self.signedPreKeyStore loadSignedPreKey:10]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:15]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:20]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:25]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:30]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:35]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:40]);
}

- (void)testSignedPreKeyDeletionKeepsSomeOldKeys
{
    SignedPreKeyRecord *justUploadedSignedPreKeyRecord;
    for (int i = 1; i <= 5; i++) {
        // All these keys will be considered "old", since they were created more than 30 days ago.
        int secondsAgo = (i - 40) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[ECKeyPair generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record transaction:transaction];
        });
        justUploadedSignedPreKeyRecord = record;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.signedPreKeyStore cullSignedPreKeyRecordsWithJustUploadedSignedPreKey:justUploadedSignedPreKeyRecord
                                                                        transaction:transaction];
    });

    // We need to keep 3 "old" keys, plus the "current" key
    XCTAssertNil([self.signedPreKeyStore loadSignedPreKey:1]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:2]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:3]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:4]);
    XCTAssertNotNil([self.signedPreKeyStore loadSignedPreKey:5]);
}

@end
