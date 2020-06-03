//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "SSKSignedPreKeyStore.h"
#import "TSPreKeyManager.h"
#import <AxolotlKit/SignedPrekeyRecord.h>

@interface  TSPreKeyManager (Testing)

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *)keyId;

@end

@interface SignedPreKeyDeletionTests : SSKBaseTestObjC

@end

@implementation SignedPreKeyDeletionTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return SSKEnvironment.shared.signedPreKeyStore;
}

- (NSUInteger)signedPreKeyCount
{
    return [self.signedPreKeyStore loadSignedPreKeys].count;
}

- (void)testSignedPreKeyDeletion {
    XCTAssertEqual(0, self.signedPreKeyCount);

    int days = 20;
    int lastPreKeyId = days;

    for (int i = 0; i <= days; i++) { // 21 signed keys are generated, one per day from now until 20 days ago.
        int secondsAgo = (i - days) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[Curve25519 generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record];
    }

    // Sanity check
    XCTAssertEqual(21, self.signedPreKeyCount);

    [TSPreKeyManager clearSignedPreKeyRecordsWithKeyId:@(lastPreKeyId)];

    XCTAssert([self.signedPreKeyStore loadSignedPreKey:lastPreKeyId] != nil);

    // We'll delete every key created 7 or more days ago.
    XCTAssertEqual(7, self.signedPreKeyCount);
}

- (void)testSignedPreKeyDeletionKeepsSomeOldKeys
{
    XCTAssertEqual(0, self.signedPreKeyCount);

    int lastPreKeyId = 10;
    for (int i = 0; i <= 10; i++) {
        // All these keys will be considered "old", since they were created more than 7 days ago.
        int secondsAgo = (i - 20) * 24 * 60 * 60;
        NSAssert(secondsAgo <= 0, @"Time in past must be negative");
        NSDate *generatedAt = [NSDate dateWithTimeIntervalSinceNow:secondsAgo];
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i
                                                                    keyPair:[Curve25519 generateKeyPair]
                                                                  signature:[NSData new]
                                                                generatedAt:generatedAt];
        // we only retain accepted keys
        [record markAsAcceptedByService];
        [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record];
    }

    // Sanity check
    XCTAssertEqual(11, self.signedPreKeyCount);

    [TSPreKeyManager clearSignedPreKeyRecordsWithKeyId:@(lastPreKeyId)];

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
        [self.signedPreKeyStore storeSignedPreKey:i signedPreKeyRecord:record];
    }

    // Sanity check
    XCTAssertEqual(4, self.signedPreKeyCount);

    [TSPreKeyManager clearSignedPreKeyRecordsWithKeyId:@(lastPreKeyId)];
    XCTAssert([self.signedPreKeyStore loadSignedPreKey:lastPreKeyId] != nil);

    // All records should still be stored.
    XCTAssertEqual(4, self.signedPreKeyCount);
}

@end
