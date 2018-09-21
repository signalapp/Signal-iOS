//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSRecipientIdentity.h"
#import "SSKBaseTest.h"
#import "SSKEnvironment.h"
#import "YapDatabaseConnection+OWS.h"
#import <Curve25519Kit/Curve25519.h>
#import <Curve25519Kit/Randomness.h>

extern NSString *const OWSPrimaryStorageTrustedKeysCollection;

@interface TSStorageIdentityKeyStoreTests : SSKBaseTest

@end

@implementation TSStorageIdentityKeyStoreTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testNewEmptyKey
{
    NSData *newKey = [Randomness generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";

    [self
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionOutgoing
                                                               protocolContext:transaction]);
            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionIncoming
                                                               protocolContext:transaction]);
        }];
}

- (void)testAlreadyRegisteredKey
{
    NSData *newKey = [Randomness generateRandomBytes:32];
    NSString *recipientId = @"test@gmail.com";

    [self
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSIdentityManager sharedManager] saveRemoteIdentity:newKey
                                                       recipientId:recipientId
                                                   protocolContext:transaction];

            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionOutgoing
                                                               protocolContext:transaction]);
            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:newKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionIncoming
                                                               protocolContext:transaction]);
        }];
}


- (void)testChangedKey
{
    NSData *originalKey = [Randomness generateRandomBytes:32];
    NSString *recipientId = @"test@protonmail.com";

    [self
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSIdentityManager sharedManager] saveRemoteIdentity:originalKey
                                                       recipientId:recipientId
                                                   protocolContext:transaction];

            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:originalKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionOutgoing
                                                               protocolContext:transaction]);
            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:originalKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionIncoming
                                                               protocolContext:transaction]);

            NSData *otherKey = [Randomness generateRandomBytes:32];

            XCTAssertFalse([[OWSIdentityManager sharedManager] isTrustedIdentityKey:otherKey
                                                                        recipientId:recipientId
                                                                          direction:TSMessageDirectionOutgoing
                                                                    protocolContext:transaction]);
            XCTAssert([[OWSIdentityManager sharedManager] isTrustedIdentityKey:otherKey
                                                                   recipientId:recipientId
                                                                     direction:TSMessageDirectionIncoming
                                                               protocolContext:transaction]);
        }];
}

- (void)testIdentityKey
{
    [[OWSIdentityManager sharedManager] generateNewIdentityKey];

    XCTAssert([[[OWSIdentityManager sharedManager] identityKeyPair].publicKey length] == 32);
}

@end
