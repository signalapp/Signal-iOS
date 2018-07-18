//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "TSAccountManager.h"

//#import "TSStorageManager+keyingMaterial.h"
#import <XCTest/XCTest.h>

@interface TSAccountManager (Testing)

- (void)storeLocalNumber:(NSString *)localNumber;

@end

@interface SignalRecipientTest : XCTestCase

@property (nonatomic) NSString *localNumber;

@end

@implementation SignalRecipientTest

- (void)setUp
{
    [super setUp];
    self.localNumber = @"+13231231234";
    [[TSAccountManager sharedInstance] storeLocalNumber:self.localNumber];
}

- (void)testSelfRecipientWithExistingRecord
{
    // Sanity Check
    XCTAssertNotNil(self.localNumber);
    [[[SignalRecipient alloc] initWithTextSecureIdentifier:self.localNumber relay:nil] save];
    XCTAssertNotNil([SignalRecipient recipientWithTextSecureIdentifier:self.localNumber]);

    SignalRecipient *me = [SignalRecipient selfRecipient];
    XCTAssert(me);
    XCTAssertEqualObjects(self.localNumber, me.uniqueId);
}

- (void)testSelfRecipientWithoutExistingRecord
{
    XCTAssertNotNil(self.localNumber);
    [[SignalRecipient fetchObjectWithUniqueID:self.localNumber] remove];
    // Sanity Check that there's no existing user.
    XCTAssertNil([SignalRecipient recipientWithTextSecureIdentifier:self.localNumber]);

    SignalRecipient *me = [SignalRecipient selfRecipient];
    XCTAssert(me);
    XCTAssertEqualObjects(self.localNumber, me.uniqueId);
}

@end
