//
//  SignedPreKeyDeletionTests.m
//  Signal
//
//  Created by Frederic Jacobs on 27/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <AxolotlKit/SignedPrekeyRecord.h>
#import <25519/Curve25519.h>
#import <25519/Ed25519.h>

#import "TSPreKeyManager.h"
#import "TSStorageManager+SignedPreKeyStore.h"

@interface  TSPreKeyManager ()

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber*)keyId;

@end


@interface SignedPreKeyDeletionTests : XCTestCase

@property int lastpreKeyId;

@end

@implementation SignedPreKeyDeletionTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testSignedPreKeyDeletion {
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:TSStorageManagerSignedPreKeyStoreCollection];
    }];
    
    _lastpreKeyId = 20;
    
    for (int i = 0; i <= _lastpreKeyId; i++) { // 21 signed keys are generated, one per day from now until 20 days ago.
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i keyPair:[Curve25519 generateKeyPair] signature:nil generatedAt:[NSDate dateWithTimeIntervalSinceNow:i*24*60*60]];
        [[TSStorageManager sharedManager] storeSignedPreKey:i signedPreKeyRecord:record];
    }
    
    
    [TSPreKeyManager clearSignedPreKeyRecordsWithKeyId:[NSNumber numberWithInt:_lastpreKeyId]];
    
    
    XCTAssert([[TSStorageManager sharedManager]loadSignedPrekey:_lastpreKeyId] != nil);
    
    // We tolerate to keep keys around for 14 days. We have 20-15 = 5 keys to delete. Hence the result of 21-5 = 16
    XCTAssert([[[TSStorageManager sharedManager] loadSignedPreKeys] count] == 16);
}


- (void)testOlderRecordsNotDeletedIfNoReplacement {
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:TSStorageManagerSignedPreKeyStoreCollection];
    }];
    
    _lastpreKeyId = 3;
        
    for (int i = 1; i <= _lastpreKeyId; i++) { // 21 signed keys are generated, one per day from now until 20 days ago.
        SignedPreKeyRecord *record = [[SignedPreKeyRecord alloc] initWithId:i keyPair:[Curve25519 generateKeyPair] signature:nil generatedAt:[NSDate dateWithTimeIntervalSinceNow:i*100*24*60*60]];
        [[TSStorageManager sharedManager] storeSignedPreKey:i signedPreKeyRecord:record];
    }
    
    
    [TSPreKeyManager clearSignedPreKeyRecordsWithKeyId:[NSNumber numberWithInt:_lastpreKeyId]];
    
    
    XCTAssert([[TSStorageManager sharedManager]loadSignedPrekey:_lastpreKeyId] != nil);
    // All three records should still be stored.
    XCTAssert([[[TSStorageManager sharedManager] loadSignedPreKeys] count] == 3);
}

@end
