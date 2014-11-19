//
//  TSStorageIdentityKeyStoreTests.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <25519/Curve25519.h>

#import "TSStorageManager+IdentityKeyStore.h"
#import "SecurityUtils.h"

@interface TSStorageIdentityKeyStoreTests : XCTestCase

@end

@implementation TSStorageIdentityKeyStoreTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testNewEmptyKey {
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId]);
}

- (void)testAlreadyRegisteredKey {
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";
    
    [[TSStorageManager sharedManager] saveRemoteIdentity:newKey recipientId:recipientId];
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId]);
}


- (void)testChangedKey {
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";
    
    [[TSStorageManager sharedManager] saveRemoteIdentity:newKey recipientId:recipientId];
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId]);
    
    NSData *otherKey = [SecurityUtils generateRandomBytes:32];
    
    XCTAssertFalse([[TSStorageManager sharedManager] isTrustedIdentityKey:otherKey recipientId:recipientId]);
}

- (void)testIdentityKey {
    [[TSStorageManager sharedManager] generateNewIdentityKey];
    
    XCTAssert([[[TSStorageManager sharedManager] identityKeyPair].publicKey length] == 32);
}

@end
