//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "SignalRecipient.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

@interface SignalRecipientTest : XCTestCase

@end

@implementation SignalRecipientTest

- (void)setUp {
    [super setUp];
    [TSStorageManager storePhoneNumber:@"+13231231234"];
}

- (void)testSelfRecipientWithExistingRecord
{
    // Sanity Check
    NSString *localNumber = @"+13231231234";
    XCTAssertNotNil(localNumber);
    [[[SignalRecipient alloc] initWithTextSecureIdentifier:localNumber relay:nil supportsVoice:YES] save];
    XCTAssertNotNil([SignalRecipient recipientWithTextSecureIdentifier:localNumber]);

    SignalRecipient *me = [SignalRecipient selfRecipient];
    XCTAssert(me);
    XCTAssertEqualObjects(localNumber, me.uniqueId);
}

- (void)testSelfRecipientWithoutExistingRecord
{
    NSString *localNumber = @"+13231231234";
    XCTAssertNotNil(localNumber);
    [[SignalRecipient fetchObjectWithUniqueID:localNumber] remove];
    // Sanity Check that there's no existing user.
    XCTAssertNil([SignalRecipient recipientWithTextSecureIdentifier:localNumber]);

    SignalRecipient *me = [SignalRecipient selfRecipient];
    XCTAssert(me);
    XCTAssertEqualObjects(localNumber, me.uniqueId);
}

@end
