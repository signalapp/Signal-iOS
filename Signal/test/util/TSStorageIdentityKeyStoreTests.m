//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSRecipientIdentity.h"
#import "OWSUnitTestEnvironment.h"
#import "SSKBaseTest.h"
#import "SSKEnvironment.h"
#import "SecurityUtils.h"
#import <Curve25519Kit/Curve25519.h>

@interface TSStorageIdentityKeyStoreTests : SSKBaseTest

@end

@implementation TSStorageIdentityKeyStoreTests

- (void)setUp
{
    [super setUp];

    [[OWSPrimaryStorage sharedManager] purgeCollection:OWSPrimaryStorageTrustedKeysCollection];
    [OWSRecipientIdentity removeAllObjectsInCollection];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testNewEmptyKey
{
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";

    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionOutgoing]);
    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionIncoming]);
}

- (void)testAlreadyRegisteredKey
{
    NSData *newKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";

    [[OWSIdentityManager sharedManager] saveRemoteIdentity:newKey recipientId:recipientId];

    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionOutgoing]);
    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionIncoming]);
}


- (void)testChangedKey
{
    NSData *originalKey = [SecurityUtils generateRandomBytes:32];
    NSString *recipientId = @"test@protonmail.com";

    [[OWSIdentityManager sharedManager] saveRemoteIdentity:originalKey recipientId:recipientId];

    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:originalKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionOutgoing]);
    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:originalKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionIncoming]);

    NSData *otherKey = [SecurityUtils generateRandomBytes:32];

    XCTAssertFalse([[OWSIdentityManager sharedManager] isTrustedIdentityKey:otherKey
                                                                recipientId:recipientId
                                                                  direction:TSMessageDirectionOutgoing]);
    XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:otherKey
                                                           recipientId:recipientId
                                                             direction:TSMessageDirectionIncoming]);
}


- (void)testIdentityKey
{
    [[OWSIdentityManager sharedManager] generateNewIdentityKey];

    XCTAssert([[[OWSIdentityManager sharedManager] identityKeyPair].publicKey length] == 32);
}

@end
