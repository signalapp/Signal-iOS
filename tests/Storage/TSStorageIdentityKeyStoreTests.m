//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <25519/Curve25519.h>

#import "OWSUnitTestEnvironment.h"
#import "SecurityUtils.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

@interface TSStorageIdentityKeyStoreTests : XCTestCase

@end

@implementation TSStorageIdentityKeyStoreTests

- (void)setUp {
    [super setUp];
    [[TSStorageManager sharedManager] purgeCollection:@"TSStorageManagerTrustedKeysCollection"];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testNewEmptyKey {
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId direction:TSMessageDirectionOutgoing]);
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId direction:TSMessageDirectionIncoming]);
}

- (void)testAlreadyRegisteredKey {
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";
    
    [[TSStorageManager sharedManager] saveRemoteIdentity:newKey recipientId:recipientId];
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId direction:TSMessageDirectionOutgoing]);
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:newKey recipientId:recipientId direction:TSMessageDirectionIncoming]);
}


- (void)testChangedKey
{
    NSData *originalKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@protonmail.com";

    [[TSStorageManager sharedManager] saveRemoteIdentity:originalKey recipientId:recipientId];
    
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:originalKey recipientId:recipientId direction:TSMessageDirectionOutgoing]);
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:originalKey recipientId:recipientId direction:TSMessageDirectionIncoming]);
    
    NSData *otherKey = [SecurityUtils generateRandomBytes:32];
    
    XCTAssertFalse([[TSStorageManager sharedManager] isTrustedIdentityKey:otherKey recipientId:recipientId direction:TSMessageDirectionOutgoing]);
    XCTAssert([[TSStorageManager sharedManager] isTrustedIdentityKey:otherKey recipientId:recipientId direction:TSMessageDirectionIncoming]);
}


- (void)testIdentityKey {
    [[TSStorageManager sharedManager] generateNewIdentityKey];
    
    XCTAssert([[[TSStorageManager sharedManager] identityKeyPair].publicKey length] == 32);
}

@end
