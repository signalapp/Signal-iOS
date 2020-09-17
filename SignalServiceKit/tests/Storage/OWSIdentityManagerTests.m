//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSIdentityManager.h"
#import "OWSRecipientIdentity.h"
#import "SSKBaseTestObjC.h"
#import "SSKEnvironment.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSIdentityManagerTests : SSKBaseTestObjC

@end

@implementation OWSIdentityManagerTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager shared];
}

- (void)testNewEmptyKey
{
    NSData *newKey = [Randomness generateRandomBytes:32];
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        __unused NSString *accountId = [[OWSAccountIdFinder new] ensureAccountIdForAddress:address
                                                                               transaction:transaction];

        XCTAssert([self.identityManager isTrustedIdentityKey:newKey
                                                     address:address
                                                   direction:TSMessageDirectionOutgoing
                                                 transaction:transaction]);
        XCTAssert([self.identityManager isTrustedIdentityKey:newKey
                                                     address:address
                                                   direction:TSMessageDirectionIncoming
                                                 transaction:transaction]);
    }];
}

- (void)testAlreadyRegisteredKey
{
    NSData *newKey = [Randomness generateRandomBytes:32];
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.identityManager saveRemoteIdentity:newKey address:address transaction:transaction];

        XCTAssert([self.identityManager isTrustedIdentityKey:newKey
                                                     address:address
                                                   direction:TSMessageDirectionOutgoing
                                                 transaction:transaction]);
        XCTAssert([self.identityManager isTrustedIdentityKey:newKey
                                                     address:address
                                                   direction:TSMessageDirectionIncoming
                                                 transaction:transaction]);
    }];
}


- (void)testChangedKey
{
    NSData *originalKey = [Randomness generateRandomBytes:32];
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.identityManager saveRemoteIdentity:originalKey address:address transaction:transaction];

        XCTAssert([self.identityManager isTrustedIdentityKey:originalKey
                                                     address:address
                                                   direction:TSMessageDirectionOutgoing
                                                 transaction:transaction]);
        XCTAssert([self.identityManager isTrustedIdentityKey:originalKey
                                                     address:address
                                                   direction:TSMessageDirectionIncoming
                                                 transaction:transaction]);

        NSData *otherKey = [Randomness generateRandomBytes:32];

        XCTAssertFalse([self.identityManager isTrustedIdentityKey:otherKey
                                                          address:address
                                                        direction:TSMessageDirectionOutgoing
                                                      transaction:transaction]);
        XCTAssert([self.identityManager isTrustedIdentityKey:otherKey
                                                     address:address
                                                   direction:TSMessageDirectionIncoming
                                                 transaction:transaction]);
    }];
}

- (void)testIdentityKey
{
    [self.identityManager generateNewIdentityKey];

    XCTAssert([[self.identityManager identityKeyPair].publicKey length] == 32);
}

@end
